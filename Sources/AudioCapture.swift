import AVFoundation
import CoreMedia
import CoreGraphics
import ScreenCaptureKit
import OSLog

enum LiveError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

/// All PCM conversion runs on one serial queue; no video output or microphone is registered.
final class AudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "live-lingo.audio", qos: .userInitiated)
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var outputFormat: AVAudioFormat?
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
            self.outputFormat = format
            self.onBuffer = onBuffer
            self.onLevel = onLevel
            self.onError = onError
            self.active = true
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
            converter = nil
            inputFormat = nil
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { [weak self] in
            guard let self, self.active else { return }; self.onError?(error)
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard active, type == .audio, sample.isValid,
              let description = sample.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              let format = AVAudioFormat(streamDescription: asbd),
              let target = outputFormat else { return }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
        guard frames > 0, let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        pcm.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames),
                                                               into: pcm.mutableAudioBufferList)
        guard status == noErr else { report(LiveError.message("音频读取失败（\(status)）。")); return }
        if Date().timeIntervalSince(lastMeterTime) > 0.12 {
            lastMeterTime = Date()
            meterSamples += 1
            if let channel = pcm.floatChannelData?[0] {
                var sum: Float = 0
                for i in 0..<Int(frames) { sum += channel[i] * channel[i] }
                let rms = sqrt(Double(sum) / Double(frames))
                if meterSamples % 20 == 1 {
                    logger.notice("Audio PCM: rate=\(format.sampleRate), channels=\(format.channelCount), frames=\(frames), rms=\(rms)")
                }
                onLevel?(min(1, max(0, (20 * log10(max(rms, 0.00001)) + 60) / 60)))
            }
            else { logger.error("Non-float32 audio format: \(format.commonFormat.rawValue)") }
        }
        if format == target { onBuffer?(pcm); return }
        if inputFormat != format {
            inputFormat = format
            converter = AVAudioConverter(from: format, to: target)
        }
        guard let converter else { report(LiveError.message("无法转换语音识别所需的音频格式。")); return }
        let capacity = AVAudioFrameCount(ceil(Double(frames) * target.sampleRate / format.sampleRate)) + 64
        guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var consumed = false
        var conversionError: NSError?
        let result = converter.convert(to: converted, error: &conversionError) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return pcm
        }
        if let conversionError { report(conversionError); return }
        if result != .error, converted.frameLength > 0 { onBuffer?(converted) }
    }

    private func report(_ error: Error) { active = false; onError?(error) }
}
