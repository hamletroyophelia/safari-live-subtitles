import AVFoundation
import CoreMedia

@main struct AudioTests {
    static func sample(rate: Double, frames: Int, value: Float) -> CMSampleBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        var description: CMAudioFormatDescription?
        precondition(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: format.streamDescription,
            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &description) == noErr)
        var block: CMBlockBuffer?
        let bytes = frames * MemoryLayout<Float>.size
        precondition(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: bytes, flags: 0, blockBufferOut: &block) == noErr)
        let values = [Float](repeating: value, count: frames)
        values.withUnsafeBytes { raw in
            precondition(CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block!, offsetIntoDestination: 0, dataLength: bytes) == noErr)
        }
        var sample: CMSampleBuffer?
        precondition(CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault, dataBuffer: block!,
            formatDescription: description!, sampleCount: frames, presentationTimeStamp: .zero, packetDescriptions: nil, sampleBufferOut: &sample) == noErr)
        return sample!
    }
    static func main() throws {
        let target = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let converter = PCMConverter(target: target)
        let first = try converter.convert(sample(rate: 48000, frames: 480, value: 0.25), measureLevel: true)!
        precondition(first.buffer.format == target && first.buffer.frameLength > 0)
        precondition(abs(first.rms! - 0.25) < 0.0001)
        let retained = Array(UnsafeBufferPointer(start: first.buffer.floatChannelData![0], count: Int(first.buffer.frameLength)))
        for i in 0..<100 {
            let next = try converter.convert(sample(rate: 48000, frames: i % 2 == 0 ? 480 : 960, value: -0.75), measureLevel: false)!
            precondition(next.buffer !== first.buffer && next.rms == nil)
        }
        precondition(retained == Array(UnsafeBufferPointer(start: first.buffer.floatChannelData![0], count: Int(first.buffer.frameLength))), "later scratch reuse must not alter delivered audio")
        // Format changes rebuild the converter; direct-format buffers also retain independent ownership.
        let direct = try converter.convert(sample(rate: 16000, frames: 160, value: 0.125), measureLevel: true)!
        let later = try converter.convert(sample(rate: 16000, frames: 320, value: -0.5), measureLevel: true)!
        precondition(direct.buffer !== later.buffer && direct.buffer.frameLength == 160 && later.buffer.frameLength == 320)
        precondition(direct.buffer.floatChannelData![0][0] == 0.125 && abs(later.rms! - 0.5) < 0.0001)
        let changed = try converter.convert(sample(rate: 44100, frames: 441, value: 0.5), measureLevel: true)!
        precondition(changed.buffer.format == target && changed.buffer.frameLength > 0 && abs(changed.rms! - 0.5) < 0.0001)
        print("PASS: PCM resampling, meter RMS, scratch growth, retained output ownership and format changes")
    }
}
