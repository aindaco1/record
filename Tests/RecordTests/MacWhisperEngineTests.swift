import AVFoundation
import Foundation
@testable import Record
import XCTest

final class MacWhisperEngineTests: XCTestCase {
    func testTranscribesWithExactArgumentsAndConvertsMilliseconds() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let engine = try MacWhisperEngine(
            executable: fixture.executable,
            model: "whisperkit:openai_whisper-small",
            language: "en"
        )

        try await engine.prepare()
        let segments = try await engine.transcribe(fixture.audio)

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].start, 0.125, accuracy: 0.0001)
        XCTAssertEqual(segments[0].end, 0.875, accuracy: 0.0001)
        XCTAssertEqual(segments[0].text, "local fixture")
        let arguments = try String(
            contentsOf: fixture.arguments,
            encoding: .utf8
        ).split(separator: "\n").map(String.init)
        XCTAssertEqual(arguments.count, 11)
        XCTAssertEqual(
            arguments,
            [
                "transcribe",
                "--model", "whisperkit:openai_whisper-small",
                "--language", "en",
                "--no-speakers",
                "--format", "json",
                "--output", arguments[9],
                fixture.audio.path,
            ]
        )
        XCTAssertTrue(arguments[9].hasSuffix("/transcript.json"))
    }

    func testRejectsOptionLikeAndControlCharacterModelIdentifiers() throws {
        XCTAssertThrowsError(
            try MacWhisperEngine(
                executable: URL(fileURLWithPath: "/bin/false"),
                model: "--help",
                language: "auto"
            )
        )
        XCTAssertThrowsError(
            try MacWhisperEngine(
                executable: URL(fileURLWithPath: "/bin/false"),
                model: "model\nother",
                language: "auto"
            )
        )
    }

    func testPrepareRejectsMissingExecutable() async throws {
        let engine = try MacWhisperEngine(
            executable: URL(fileURLWithPath: "/missing/record-macwhisper"),
            model: "whisperkit:openai_whisper-small",
            language: "auto"
        )

        do {
            try await engine.prepare()
            XCTFail("expected a missing-executable failure")
        } catch {
            XCTAssertEqual(
                String(describing: error),
                "MacWhisper CLI is not executable at /missing/record-macwhisper"
            )
        }
    }

    private func makeFixture() throws -> (
        directory: URL,
        executable: URL,
        arguments: URL,
        audio: URL
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("record macwhisper \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("fake mw")
        let arguments = URL(fileURLWithPath: executable.path + ".args")
        let script = #"""
            #!/bin/sh
            set -eu
            printf '%s\n' "$@" > "$0.args"
            output=''
            while [ "$#" -gt 0 ]; do
                if [ "$1" = '--output' ]; then
                    shift
                    output="$1"
                fi
                shift
            done
            test -n "$output"
            printf '%s' '{"text":"local fixture","segments":[{"start":125,"end":875,"text":" local fixture "}]}' > "$output"
            """#
        try Data(script.utf8).write(to: executable, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: executable.path
        )
        let audio = directory.appendingPathComponent("input with spaces.caf")
        try writeAudio(to: audio)
        return (directory, executable, arguments, audio)
    }

    private func writeAudio(to url: URL) throws {
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            )
        )
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600)
        )
        buffer.frameLength = 1_600
        try file.write(from: buffer)
    }
}
