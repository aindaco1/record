import Foundation
import RecordCore
import XCTest

final class RecordingControlTests: XCTestCase {
    func testDictationUsesTheSelectedMicrophoneWithoutChangingSavedSources() {
        let saved = CaptureAudioConfiguration(
            includeSystemAudio: true, includeMicrophone: false,
            microphoneDeviceID: "synthetic-input")
        let dictation = RecordingControl.Mode.dictation.audioConfiguration(using: saved)
        XCTAssertTrue(dictation.includeMicrophone)
        XCTAssertFalse(dictation.includeSystemAudio)
        XCTAssertEqual(dictation.microphoneDeviceID, saved.microphoneDeviceID)
        XCTAssertEqual(RecordingControl.Mode.audio.audioConfiguration(using: saved), saved)
        XCTAssertEqual(RecordingControl.Mode.screen.audioConfiguration(using: saved), saved)
    }

    func testRepeatedCommandsCannotReverseRecordingState() throws {
        for mode in RecordingControl.Mode.allCases {
            XCTAssertEqual(
                try RecordingControl.effect(for: .start, mode: mode, in: .init(phase: .idle)),
                .start(mode))
            for phase in [RecordingControl.Phase.preparing, .recording, .paused] {
                XCTAssertEqual(
                    try RecordingControl.effect(
                        for: .start, mode: mode, in: .init(phase: phase, mode: mode)), .none)
            }
        }
        for phase in [RecordingControl.Phase.idle, .saving, .stopping] {
            XCTAssertEqual(
                try RecordingControl.effect(for: .stop, mode: nil, in: .init(phase: phase)), .none)
        }
        XCTAssertEqual(
            try RecordingControl.effect(
                for: .pause, mode: nil, in: .init(phase: .paused, mode: .screen)), .none)
        XCTAssertEqual(
            try RecordingControl.effect(
                for: .resume, mode: nil, in: .init(phase: .recording, mode: .screen)), .none)
    }

    func testBusyModesAndUnsupportedAudioPauseFailWithoutEffects() throws {
        XCTAssertThrowsError(
            try RecordingControl.effect(
                for: .start, mode: .audio, in: .init(phase: .recording, mode: .screen)))
        for action in [RecordingControl.Action.pause, .resume] {
            for mode in [RecordingControl.Mode.audio, .dictation] {
                XCTAssertThrowsError(
                    try RecordingControl.effect(
                        for: action, mode: nil, in: .init(phase: .recording, mode: mode)))
            }
        }
        XCTAssertEqual(
            try RecordingControl.effect(
                for: .stop, mode: nil, in: .init(phase: .preparing, mode: .screen)), .stop)
        XCTAssertEqual(
            try RecordingControl.effect(
                for: .stop, mode: nil, in: .init(phase: .pausing, mode: .screen)), .stop)
    }

    func testOnlyStartAcceptsAModeAndStatusNeverChangesState() throws {
        XCTAssertThrowsError(
            try RecordingControl.effect(for: .start, mode: nil, in: .init(phase: .idle)))
        for action in RecordingControl.Action.allCases where action != .start {
            XCTAssertThrowsError(
                try RecordingControl.effect(for: action, mode: .audio, in: .init(phase: .idle)))
        }
        for phase in RecordingControl.Phase.allCases {
            XCTAssertEqual(
                try RecordingControl.effect(for: .status, mode: nil, in: .init(phase: phase)), .none
            )
        }
    }

    func testRequestsExpireAndCannotCarryOverToAnotherAppInstance() throws {
        let instance = UUID()
        let now = Date(timeIntervalSince1970: 1_000)
        let request = RecordingControl.Request(instance: instance, action: .stop, now: now)
        XCTAssertNoThrow(try request.validate(instance: instance, now: now))
        XCTAssertThrowsError(try request.validate(instance: UUID(), now: now))
        XCTAssertThrowsError(
            try request.validate(instance: instance, now: now.addingTimeInterval(5)))
        XCTAssertThrowsError(
            try request.validate(instance: instance, now: now.addingTimeInterval(-10)))
        let invalid = RecordingControl.Request(
            instance: instance, action: .pause, mode: .audio, now: now)
        XCTAssertThrowsError(try invalid.validate(instance: instance, now: now))
    }

    func testRequestDecodingRejectsExtraPayloadInsteadOfIgnoringIt() throws {
        let request = RecordingControl.Request(instance: UUID(), action: .status)
        let encoded = try JSONEncoder().encode(request)
        XCTAssertEqual(
            try JSONDecoder().decode(RecordingControl.Request.self, from: encoded), request)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["path"] = "unrequested-data"
        let extra = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(RecordingControl.Request.self, from: extra))
    }
}
