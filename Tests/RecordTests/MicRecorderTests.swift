import AVFoundation
@testable import Record
import XCTest

final class MicRecorderTests: XCTestCase {
    func testVoiceProcessingStaysEnabledWithGainControlOffOnEveryEngine() throws {
        for _ in 0..<2 {
            let input = VoiceProcessingInputStub()
            try MicRecorder.configureVoiceProcessing(on: input, automaticGainControl: false)
            XCTAssertEqual(input.changes, ["voice:true", "gain:false"])
            XCTAssertFalse(input.isVoiceProcessingAGCEnabled)
            XCTAssertFalse(
                input.voiceProcessingOtherAudioDuckingConfiguration.enableAdvancedDucking.boolValue)
            XCTAssertEqual(input.voiceProcessingOtherAudioDuckingConfiguration.duckingLevel, .min)
        }
    }

    func testGainControlCanBeEnabledWithoutChangingDucking() throws {
        let input = VoiceProcessingInputStub()
        try MicRecorder.configureVoiceProcessing(on: input, automaticGainControl: true)
        XCTAssertEqual(input.changes, ["voice:true", "gain:true"])
        XCTAssertTrue(input.isVoiceProcessingAGCEnabled)
        XCTAssertEqual(input.voiceProcessingOtherAudioDuckingConfiguration.duckingLevel, .min)
    }

    func testUnavailableVoiceProcessingDoesNotApplyGainControlToRawInput() {
        let input = VoiceProcessingInputStub()
        input.failsToEnable = true
        XCTAssertThrowsError(
            try MicRecorder.configureVoiceProcessing(on: input, automaticGainControl: false))
        XCTAssertEqual(input.changes, ["voice:true"])
    }

    func testUnsupportedFormatErrorSnapshotsSendableDiagnostic() throws {
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000,
                channels: 2,
                interleaved: false
            )
        )

        let error = MicRecorder.RecorderError.unsupportedFormat(format)

        requireSendable(error)
        XCTAssertTrue(error.description.contains("can't downmix mic format"))
        XCTAssertTrue(error.description.contains("48000"))
    }

    private func requireSendable<T: Sendable>(_ value: T) {}
}

private final class VoiceProcessingInputStub: MicrophoneVoiceProcessingInput {
    enum Failure: Error { case unavailable }
    var changes: [String] = []
    var failsToEnable = false
    var isVoiceProcessingAGCEnabled = true {
        didSet { changes.append("gain:\(isVoiceProcessingAGCEnabled)") }
    }
    var voiceProcessingOtherAudioDuckingConfiguration =
        AVAudioVoiceProcessingOtherAudioDuckingConfiguration(
            enableAdvancedDucking: true, duckingLevel: .default)

    func setVoiceProcessingEnabled(_ enabled: Bool) throws {
        changes.append("voice:\(enabled)")
        if failsToEnable { throw Failure.unavailable }
    }
}
