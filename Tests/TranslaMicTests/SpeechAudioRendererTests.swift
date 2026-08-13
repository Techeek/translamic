import AVFoundation
import XCTest
@testable import TranslaMic

final class SpeechAudioRendererTests: XCTestCase {
    func testMossPCMChunkConvertsLittleEndianInt16ToFloatSamples() throws {
        let pcm = Data([
            0x00, 0x80,
            0x00, 0x00,
            0xFF, 0x7F,
        ])

        let buffer = try XCTUnwrap(SpeechAudioRenderer.buffer(
            from: MossAudioChunk(pcmData: pcm, sampleRate: 48_000)
        ))
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])

        XCTAssertEqual(buffer.frameLength, 3)
        XCTAssertEqual(buffer.format.sampleRate, 48_000)
        XCTAssertEqual(samples[0], -1.0, accuracy: 0.000_01)
        XCTAssertEqual(samples[1], 0.0, accuracy: 0.000_01)
        XCTAssertEqual(samples[2], Float(Int16.max) / 32768.0, accuracy: 0.000_01)
    }
}
