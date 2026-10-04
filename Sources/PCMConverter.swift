import AVFoundation
import CoreMedia
import Accelerate

enum LiveError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

struct ConvertedAudio {
    let buffer: AVAudioPCMBuffer
    let sourceFormat: AVAudioFormat
    let rms: Double?
}

/// Used exclusively on the audio serial queue. Delivered buffers are never reused.
final class PCMConverter {
    private let target: AVAudioFormat
    private var description: CMAudioFormatDescription?
    private var format: AVAudioFormat?
    private var scratch: AVAudioPCMBuffer?
    private var converter: AVAudioConverter?

    init(target: AVAudioFormat) { self.target = target }

    func convert(_ sample: CMSampleBuffer, measureLevel: Bool) throws -> ConvertedAudio? {
        guard sample.isValid, let nextDescription = sample.formatDescription else { return nil }
        if description == nil || !CMFormatDescriptionEqual(description!, otherFormatDescription: nextDescription) {
            guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(nextDescription),
                  let nextFormat = AVAudioFormat(streamDescription: asbd) else { return nil }
            description = nextDescription
            format = nextFormat
            scratch = nil
            converter = nextFormat == target ? nil : AVAudioConverter(from: nextFormat, to: target)
        }
        guard let format else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
        guard frames > 0 else { return nil }
        let pcm: AVAudioPCMBuffer
        if format == target {
            guard let owned = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
            pcm = owned
        } else {
            // The converter consumes input synchronously; only its scratch input can be reused.
            if scratch == nil || scratch!.frameCapacity < frames {
                scratch = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
            }
            guard let scratch else { return nil }
            pcm = scratch
        }
        pcm.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames), into: pcm.mutableAudioBufferList)
        guard status == noErr else { throw LiveError.message("音频读取失败（\(status)）。") }
        var rms: Double?
        if measureLevel, let channel = pcm.floatChannelData?[0] {
            var value: Float = 0
            vDSP_rmsqv(channel, 1, &value, vDSP_Length(frames))
            rms = Double(value)
        }
        if format == target { return ConvertedAudio(buffer: pcm, sourceFormat: format, rms: rms) }
        guard let converter else { throw LiveError.message("无法转换语音识别所需的音频格式。") }
        let capacity = AVAudioFrameCount(ceil(Double(frames) * target.sampleRate / format.sampleRate)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var consumed = false
        var conversionError: NSError?
        let result = converter.convert(to: output, error: &conversionError) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return pcm
        }
        if let conversionError { throw conversionError }
        guard result != .error, output.frameLength > 0 else { return nil }
        return ConvertedAudio(buffer: output, sourceFormat: format, rms: rms)
    }
}
