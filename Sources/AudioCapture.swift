import AVFoundation
import CoreMedia
import CoreGraphics
import ScreenCaptureKit
import OSLog

/// All PCM conversion runs on one serial queue; no video output or microphone is registered.
final class AudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "live-lingo.audio", qos: .userInitiated)
    private var pcmConverter: PCMConverter?
    private var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    private var onLevel: ((Double) -> Void)?
    private var onError: ((Error) -> Void)?
    private var lastMeterTime = Date.distantPast
    private var active = false
    @MainActor private let picker = ContentPicker()
    private let logger = Logger(subsystem: "local.livelingo.safari-live-subtitles", category: "audio")
    private var meterSamples = 0

    @MainActor func start(source: CaptureSource, format: AVAudioFormat,
               onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
               onLevel: @escaping (Double) -> Void,
               onError: @escaping (Error) -> Void) async throws {
        let filter: SCContentFilter
        if !CGPreflightScreenCaptureAccess() {
            filter = try await picker.select(source: source)
        } else {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            try Task.checkCancellation()
            guard let display = content.displays.first else { throw LiveError.message("未找到可用显示器。") }
            if source == .safari {
                let apps = content.applications.filter { $0.bundleIdentifier == "com.apple.Safari" }
                guard !apps.isEmpty else { throw LiveError.message("请先打开 Safari 并播放直播，再点击开始。") }
                filter = SCContentFilter(display: display, including: apps, exceptingWindows: [])
            } else {
                let own = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
                filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
            }
        }
        try Task.checkCancellation()
        let apps = filter.includedApplications.map(\.bundleIdentifier)
        logger.notice("Selected source: \(source.rawValue, privacy: .public), includesSafari: \(apps.contains("com.apple.Safari")), filterStyle: \(filter.style.rawValue)")
        if source == .safari, !apps.contains("com.apple.Safari") {
            throw LiveError.message("系统选择的来源不是 Safari 应用。请再次开始并选中 Safari。")
        }
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.captureMicrophone = false
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 1
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.queueDepth = 3
        config.showsCursor = false
        queue.sync {
            self.pcmConverter = PCMConverter(target: format)
            self.onBuffer = onBuffer
            self.onLevel = onLevel
            self.onError = onError
            self.active = true
            self.lastMeterTime = .distantPast
            self.meterSamples = 0
        }
        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        // Audio only: ScreenCaptureKit never delivers screen image buffers to this app.
        try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        stream = newStream
        do { try await newStream.startCapture(); try Task.checkCancellation() }
        catch { await stop(); throw error }
    }

    @MainActor func stop() async {
        picker.close()
        if let stream { try? await stream.stopCapture() }
        stream = nil
        queue.sync {
            active = false
            onBuffer = nil
            onLevel = nil
            onError = nil
            pcmConverter = nil
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { [weak self] in
            guard let self, self.active else { return }; self.onError?(error)
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard active, type == .audio, let pcmConverter else { return }
        let meterDue = Date().timeIntervalSince(lastMeterTime) > 0.2
        do {
            guard let audio = try pcmConverter.convert(sample, measureLevel: meterDue) else { return }
            if meterDue {
                lastMeterTime = Date()
                meterSamples += 1
                if let rms = audio.rms {
                    if meterSamples == 1 {
                        logger.notice("Audio PCM: rate=\(audio.sourceFormat.sampleRate), channels=\(audio.sourceFormat.channelCount), frames=\(audio.buffer.frameLength), rms=\(rms)")
                    }
                    onLevel?(min(1, max(0, (20 * log10(max(rms, 0.00001)) + 60) / 60)))
                }
            }
            onBuffer?(audio.buffer)
        } catch { report(error) }
    }

    private func report(_ error: Error) { active = false; onError?(error) }
}
