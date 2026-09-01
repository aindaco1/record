import AppKit
import CoreGraphics
import Foundation
import ImageIO
import RecordCore
import UniformTypeIdentifiers

enum ScreenshotImageEncodingError: Error, Equatable {
    case destinationUnavailable
    case encodingFailed
    case jpegCanvasUnavailable
    case invalidEncodedImage
}

struct ScreenshotImageEncoder: Sendable {
    func encode(
        _ image: CGImage,
        format: ScreenshotImageFormat,
        jpegQuality: Double = 0.95
    ) throws -> Data {
        let outputImage: CGImage
        let type: UTType
        let properties: [CFString: Any]
        switch format {
        case .png:
            outputImage = image
            type = .png
            properties = [:]
        case .jpeg:
            outputImage = try flattenedOnWhite(image)
            type = .jpeg
            properties = [
                kCGImageDestinationLossyCompressionQuality: min(1, max(0.5, jpegQuality))
            ]
        }

        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data,
                type.identifier as CFString,
                1,
                nil
            )
        else {
            throw ScreenshotImageEncodingError.destinationUnavailable
        }
        CGImageDestinationAddImage(destination, outputImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenshotImageEncodingError.encodingFailed
        }
        let encoded = data as Data
        try validate(encoded, format: format, expectedImage: outputImage)
        return encoded
    }

    func validate(
        _ data: Data,
        format: ScreenshotImageFormat,
        expectedImage: CGImage
    ) throws {
        guard
            !data.isEmpty,
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let type = CGImageSourceGetType(source),
            UTType(type as String)?.conforms(to: format == .png ? .png : .jpeg) == true,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
            properties[kCGImagePropertyPixelWidth] as? Int == expectedImage.width,
            properties[kCGImagePropertyPixelHeight] as? Int == expectedImage.height
        else {
            throw ScreenshotImageEncodingError.invalidEncodedImage
        }
    }

    private func flattenedOnWhite(_ image: CGImage) throws -> CGImage {
        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard
            let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            throw ScreenshotImageEncodingError.jpegCanvasUnavailable
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let flattened = context.makeImage() else {
            throw ScreenshotImageEncodingError.jpegCanvasUnavailable
        }
        return flattened
    }
}

enum ScreenshotExportError: Error, Equatable {
    case destinationUnavailable
    case publicationFailed
    case invalidPublishedFile
}

struct ScreenshotExporter: Sendable {
    init() {}

    func publish(
        data: Data,
        image: CGImage,
        format: ScreenshotImageFormat,
        directory: URL,
        capturedAt: Date
    ) throws -> URL {
        let fileManager = FileManager.default
        var isDirectory = ObjCBool(false)
        guard
            fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw ScreenshotExportError.destinationUnavailable
        }

        let temporary = directory.appendingPathComponent(
            ".record-screenshot-\(UUID().uuidString).partial",
            isDirectory: false
        )
        defer { try? fileManager.removeItem(at: temporary) }
        do {
            try data.write(to: temporary, options: .withoutOverwriting)
        } catch {
            throw ScreenshotExportError.publicationFailed
        }

        do {
            try ScreenshotImageEncoder().validate(data, format: format, expectedImage: image)
        } catch {
            throw ScreenshotExportError.invalidPublishedFile
        }

        var destination = ScreenshotFileNamePolicy.nextAvailableURL(
            in: directory,
            at: capturedAt,
            format: format,
            fileExists: { fileManager.fileExists(atPath: $0.path) }
        )
        while true {
            do {
                try fileManager.moveItem(at: temporary, to: destination)
                break
            } catch CocoaError.fileWriteFileExists {
                destination = ScreenshotFileNamePolicy.nextAvailableURL(
                    in: directory,
                    at: capturedAt,
                    format: format,
                    fileExists: { fileManager.fileExists(atPath: $0.path) }
                )
            } catch {
                throw ScreenshotExportError.publicationFailed
            }
        }
        guard LocalFilePolicy.isNonemptyRegularFile(destination) else {
            throw ScreenshotExportError.invalidPublishedFile
        }
        return destination
    }
}

@MainActor
final class ScreenshotPasteboardWriter {
    enum PasteboardError: Error, Equatable {
        case rejected
    }

    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func writePNG(_ data: Data) throws {
        pasteboard.clearContents()
        guard pasteboard.setData(data, forType: .png) else {
            throw PasteboardError.rejected
        }
    }
}
