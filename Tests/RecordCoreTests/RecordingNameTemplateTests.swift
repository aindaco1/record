import Foundation
@testable import RecordCore
import XCTest

final class RecordingNameTemplateTests: XCTestCase {
    func testRendersDateTimeAndDeterministicBundledWords() throws {
        let template = try RecordingNameTemplate(
            validating: "{date} at {time} - {color} {animal}"
        )

        XCTAssertEqual(
            template.render(
                at: Date(timeIntervalSince1970: 0),
                timeZone: try XCTUnwrap(TimeZone(secondsFromGMT: 0)),
                wordSeed: 0
            ),
            "1970-01-01 at 00.00.00 - Amber Falcon"
        )
    }

    func testClipboardIsRequiredAndSanitizedOnlyWhenReferenced() throws {
        let withoutClipboard = try RecordingNameTemplate(validating: "{date}")
        let withClipboard = try RecordingNameTemplate(validating: "PR {clipboard}")

        XCTAssertFalse(withoutClipboard.requiresClipboard)
        XCTAssertTrue(withClipboard.requiresClipboard)
        XCTAssertEqual(
            withClipboard.render(
                at: Date(timeIntervalSince1970: 0),
                clipboard: "../secret:\nname"
            ),
            "PR secret name"
        )
    }

    func testEscapedBracesRemainLiteral() throws {
        let template = try RecordingNameTemplate(validating: "{{draft}} {name}")
        XCTAssertEqual(
            template.render(at: Date(timeIntervalSince1970: 0), wordSeed: 0),
            "{draft} Alex"
        )
    }

    func testUnknownAndUnmatchedTokensFailClosed() {
        XCTAssertThrowsError(try RecordingNameTemplate(validating: "{unknown}")) {
            XCTAssertEqual(
                $0 as? RecordingNameTemplate.TemplateError,
                .unknownToken("unknown")
            )
        }
        XCTAssertThrowsError(try RecordingNameTemplate(validating: "{date")) {
            XCTAssertEqual($0 as? RecordingNameTemplate.TemplateError, .unmatchedBrace)
        }
    }

    func testRenderedNameIsLengthBoundedAndNeverEmpty() throws {
        let long = try RecordingNameTemplate(validating: String(repeating: "a", count: 200))
        let empty = try RecordingNameTemplate(validating: "{clipboard}")

        XCTAssertEqual(long.render(at: Date()).count, 120)
        XCTAssertEqual(empty.render(at: Date(), clipboard: "///"), "Record")
    }

    func testRenderedNameIsBoundedByUTF8BytesWithoutSplittingCharacters() throws {
        let template = try RecordingNameTemplate(validating: "{clipboard}")

        let rendered = template.render(
            at: Date(timeIntervalSince1970: 0),
            clipboard: String(repeating: "🙂", count: 100)
        )

        XCTAssertEqual(rendered.count, 50)
        XCTAssertEqual(rendered.utf8.count, RecordingNameTemplate.maximumRenderedUTF8Bytes)
        XCTAssertTrue(LocalFileNamePolicy.isSafeComponent(rendered))
    }
}
