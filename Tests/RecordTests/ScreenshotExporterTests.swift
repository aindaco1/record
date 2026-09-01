import AppKit
import CoreGraphics
import Foundation
import ImageIO
import RecordCore
@testable import Record
import UniformTypeIdentifiers
import XCTest

final class ScreenshotExporterTests: XCTestCase {
    func testPNGEncodingIsLosslessAndPreservesNativeDimensions() throws {
        let image = try makeImage(width: 5_120, height: 32, alpha: 0.5)
        let data = try ScreenshotImageEncoder().encode(image, format: .png)
        let decoded = try decode(data)

        XCTAssertEqual(decoded.width, 5_120)
        XCTAssertEqual(decoded.height, 32)
        XCTAssertEqual(CGImageSourceGetType(try source(data)) as String?, UTType.png.identifier)
    }

    func testJPEGFlattensTransparencyOntoWhiteAtHighQuality() throws {
        let image = try makeImage(width: 64, height: 32, alpha: 0)
        let data = try ScreenshotImageEncoder().encode(
            image,
            format: .jpeg,
            jpegQuality: 0.95
        )
        let decoded = try decode(data)

        XCTAssertEqual(decoded.width, 64)
        XCTAssertEqual(decoded.height, 32)
        XCTAssertEqual(CGImageSourceGetType(try source(data)) as String?, UTType.jpeg.identifier)
        let color = try XCTUnwrap(
            NSBitmapImageRep(cgImage: decoded).colorAt(x: 32, y: 16)?
                .usingColorSpace(.sRGB)
        )
        XCTAssertGreaterThan(color.redComponent, 0.98)
        XCTAssertGreaterThan(color.greenComponent, 0.98)
        XCTAssertGreaterThan(color.blueComponent, 0.98)
    }

    func testPublicationIsAtomicCollisionSafeAndLeavesNoPartial() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ScreenshotExporterTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let image = try makeImage(width: 64, height: 32, alpha: 1)
        let data = try ScreenshotImageEncoder().encode(image, format: .png)
        let date = Date(timeIntervalSince1970: 0)
        let exporter = ScreenshotExporter()

        let first = try exporter.publish(
            data: data,
            image: image,
            format: .png,
            directory: directory,
            capturedAt: date
        )
        let second = try exporter.publish(
            data: data,
            image: image,
            format: .png,
            directory: directory,
            capturedAt: date
        )

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(LocalFilePolicy.isNonemptyRegularFile(first))
        XCTAssertTrue(LocalFilePolicy.isNonemptyRegularFile(second))
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).contains { $0.pathExtension == "partial" }
        )
    }

    func testDisplayLocatorUsesPointerDisplayAndFailsOverDeterministically() {
        let displays = [
            ScreenshotDisplayDescriptor(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100)),
            ScreenshotDisplayDescriptor(
                id: 2, frame: CGRect(x: 100, y: 0, width: 100, height: 100)),
        ]

        XCTAssertEqual(
            ScreenshotDisplayLocator.displayID(
                containing: CGPoint(x: 150, y: 50),
                displays: displays
            ),
            2
        )
        XCTAssertEqual(
            ScreenshotDisplayLocator.displayID(
                containing: CGPoint(x: 500, y: 500),
                displays: displays
            ),
            1
        )
    }

    @MainActor
    func testPasteboardWriterPublishesLosslessPNGData() throws {
        let name = NSPasteboard.Name("ScreenshotExporterTests-\(UUID().uuidString)")
        let pasteboard = NSPasteboard(name: name)
        defer { pasteboard.releaseGlobally() }
        let image = try makeImage(width: 16, height: 16, alpha: 1)
        let png = try ScreenshotImageEncoder().encode(image, format: .png)

        try ScreenshotPasteboardWriter(pasteboard: pasteboard).writePNG(png)

        XCTAssertEqual(pasteboard.data(forType: .png), png)
    }

    private func makeImage(width: Int, height: Int, alpha: CGFloat) throws -> CGImage {
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: alpha))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func source(_ data: Data) throws -> CGImageSource {
        try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    }

    private func decode(_ data: Data) throws -> CGImage {
        try XCTUnwrap(CGImageSourceCreateImageAtIndex(source(data), 0, nil))
    }
}
