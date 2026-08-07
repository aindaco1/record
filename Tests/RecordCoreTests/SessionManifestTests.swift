import Foundation
import RecordCore
import XCTest

final class SessionManifestTests: XCTestCase {
    func testManifestRoundTripsAndFinalizesAtomically() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let ended = started.addingTimeInterval(65)
        let original = SessionManifest(
            id: UUID(uuidString: "A7909C37-16C7-4F2B-A84E-E18C802593F4")!,
            startedAt: started,
            tracks: [.init(kind: .microphone, filename: "mic.caf", speaker: "me")],
            healthEvents: [
                .init(
                    track: .microphone,
                    code: .routeRecovered,
                    severity: .information,
                    occurredAtMilliseconds: 2_000,
                    durationMilliseconds: 500
                )
            ]
        )

        try original.write(to: directory)
        let finalized = try original.finalized(at: ended, tracks: original.tracks)
        try finalized.write(to: directory)

        XCTAssertEqual(try SessionManifest.read(from: directory), finalized)
        XCTAssertEqual(finalized.state, .finalized)
        XCTAssertEqual(finalized.endedAt, ended)
    }

    func testManifestRejectsInvalidTransitions() throws {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let manifest = SessionManifest(startedAt: started, tracks: [])
        let finalized = try manifest.finalized(at: started, tracks: [])

        XCTAssertThrowsError(try finalized.finalized(at: started, tracks: [])) { error in
            XCTAssertEqual(
                error as? SessionManifest.ManifestError,
                .invalidTransition(from: .finalized, to: .finalized)
            )
        }
        XCTAssertThrowsError(
            try manifest.finalized(at: started.addingTimeInterval(-1), tracks: [])
        ) { error in
            XCTAssertEqual(error as? SessionManifest.ManifestError, .endBeforeStart)
        }
    }

    func testSessionFolderAllocatorAddsDeterministicCollisionSuffix() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let timeZone = TimeZone(secondsFromGMT: 0)!

        let first = try SessionFolderAllocator.createDirectory(
            under: root,
            startedAt: date,
            timeZone: timeZone
        )
        let second = try SessionFolderAllocator.createDirectory(
            under: root,
            startedAt: date,
            timeZone: timeZone
        )

        XCTAssertEqual(first.lastPathComponent, "2023.11.14-2213")
        XCTAssertEqual(second.lastPathComponent, "2023.11.14-2213-2")
    }

    func testManifestRejectsTrackPathsThatEscapeTheSession() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let traversal = SessionManifest(
            startedAt: Date(),
            tracks: [.init(kind: .microphone, filename: "../outside.caf")]
        )
        let duplicate = SessionManifest(
            startedAt: Date(),
            tracks: [
                .init(kind: .microphone, filename: "audio.caf"),
                .init(kind: .systemAudio, filename: "audio.caf"),
            ]
        )

        XCTAssertThrowsError(try traversal.write(to: directory)) { error in
            XCTAssertEqual(
                error as? SessionManifest.ManifestError,
                .unsafeTrackFilename("../outside.caf")
            )
        }
        XCTAssertThrowsError(try duplicate.write(to: directory)) { error in
            XCTAssertEqual(
                error as? SessionManifest.ManifestError,
                .duplicateTrackFilename("audio.caf")
            )
        }
    }

    func testManifestRoundTripsCrashSafeSegmentsAndEvents() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = SessionManifest(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            tracks: [.init(kind: .screen, filename: "recording.mov")],
            captureSegments: [
                .init(
                    index: 1,
                    startedAtMilliseconds: 0,
                    endedAtMilliseconds: 4_000,
                    tracks: [
                        .init(kind: .screen, filename: "segment-0001.mov"),
                        .init(
                            kind: .microphone,
                            filename: "segment-0001-mic.caf",
                            speaker: "me",
                            startOffsetMilliseconds: 12
                        ),
                    ]
                )
            ],
            captureEvents: [
                .init(kind: .started, occurredAtMilliseconds: 0, segmentIndex: 1),
                .init(kind: .paused, occurredAtMilliseconds: 4_000, segmentIndex: 1),
            ]
        )

        try manifest.write(to: directory)

        XCTAssertEqual(try SessionManifest.read(from: directory), manifest)
    }

    func testManifestRejectsUnsafeOrDuplicateSegmentMetadata() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let invalidRange = SessionManifest(
            startedAt: Date(),
            tracks: [],
            captureSegments: [
                .init(
                    index: 1,
                    startedAtMilliseconds: 100,
                    endedAtMilliseconds: 99,
                    tracks: [.init(kind: .screen, filename: "segment-0001.mov")]
                )
            ]
        )
        let duplicateFile = SessionManifest(
            startedAt: Date(),
            tracks: [.init(kind: .screen, filename: "recording.mov")],
            captureSegments: [
                .init(
                    index: 1,
                    startedAtMilliseconds: 0,
                    tracks: [.init(kind: .screen, filename: "recording.mov")]
                )
            ]
        )

        XCTAssertThrowsError(try invalidRange.write(to: directory)) { error in
            XCTAssertEqual(
                error as? SessionManifest.ManifestError,
                .invalidCaptureSegment(1)
            )
        }
        XCTAssertThrowsError(try duplicateFile.write(to: directory)) { error in
            XCTAssertEqual(
                error as? SessionManifest.ManifestError,
                .duplicateTrackFilename("recording.mov")
            )
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecordCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
