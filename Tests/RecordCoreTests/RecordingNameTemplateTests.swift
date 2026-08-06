import Foundation
import RecordCore
import XCTest

final class RecordingNameTemplateTests: XCTestCase {
    func testRendersNewKapCompatiblePlaceholdersDeterministically() throws {
        let template = RecordingNameTemplate("{date} at {time} - {color} {animal} - {clipboard}")
        let values = RecordingNameValues(
            timestamp: Date(timeIntervalSince1970: 0),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            clipboard: "PR 42",
            words: [.color: "blue", .animal: "otter"],
            wordStyle: .capitalized
        )

        XCTAssertTrue(template.requiresClipboard)
        XCTAssertEqual(
            try template.render(using: values),
            "1970-01-01 at 00.00.00 - Blue Otter - PR 42"
        )
    }

    func testEscapedBracesDoNotReadClipboard() throws {
        let template = RecordingNameTemplate("{{clipboard}} {date}")
        let values = RecordingNameValues(
            timestamp: Date(timeIntervalSince1970: 0),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertFalse(template.requiresClipboard)
        XCTAssertEqual(try template.render(using: values), "{clipboard} 1970-01-01")
    }

    func testRejectsMalformedUnknownAndMissingPlaceholders() {
        let values = RecordingNameValues(timestamp: Date())

        XCTAssertThrowsError(try RecordingNameTemplate("{date").render(using: values))
        XCTAssertThrowsError(try RecordingNameTemplate("{secret}").render(using: values)) {
            XCTAssertEqual(
                $0 as? RecordingNameTemplate.TemplateError,
                .unknownPlaceholder("secret")
            )
        }
        XCTAssertThrowsError(try RecordingNameTemplate("{animal}").render(using: values)) {
            XCTAssertEqual(
                $0 as? RecordingNameTemplate.TemplateError,
                .missingValue(.animal)
            )
        }
    }

    func testSanitizesUnsafeContentAndBoundsUTF8Length() throws {
        let template = RecordingNameTemplate(
            "{clipboard}",
            maximumCharacters: 120,
            maximumUTF8Bytes: 12
        )
        let values = RecordingNameValues(
            timestamp: Date(),
            clipboard: "../secret:\n🎥🎥🎥🎥"
        )

        let result = try template.render(using: values)

        XCTAssertFalse(result.contains("/"))
        XCTAssertFalse(result.contains(":"))
        XCTAssertLessThanOrEqual(result.utf8.count, 12)
        XCTAssertFalse(result.hasPrefix("."))
    }

    func testTinyByteLimitStillProducesSafeNonemptyName() throws {
        let result = try RecordingNameTemplate(
            "{clipboard}",
            maximumCharacters: 1,
            maximumUTF8Bytes: 1
        ).render(
            using: RecordingNameValues(timestamp: Date(), clipboard: "🎥")
        )

        XCTAssertEqual(result, "R")
        XCTAssertTrue(LocalFileNamePolicy.isSafeComponent(result))
        XCTAssertFalse(LocalFileNamePolicy.isSafeComponent("line\nbreak"))
    }

    func testAllocatorAddsCollisionSuffixWithoutOverwriting() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecordingNameTemplateTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("Demo.mov")
        try Data().write(to: first)

        let available = try RecordingNameAllocator.availableFileURL(
            in: directory,
            baseName: "Demo",
            pathExtension: ".mov"
        )

        XCTAssertEqual(available.lastPathComponent, "Demo-2.mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
    }
}
