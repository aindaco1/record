import Foundation

public struct CaptureRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    fileprivate var isValid: Bool {
        x.isFinite && y.isFinite && width.isFinite && height.isFinite
            && width > 0 && height > 0
    }
}

public enum CaptureSource: Codable, Equatable, Sendable {
    case display(id: UInt32)
    case application(bundleIdentifier: String)
    case window(id: UInt32)
    case region(displayID: UInt32, rect: CaptureRect)
}

public struct CaptureOutputSize: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    fileprivate var isAtMost4K: Bool {
        width >= 16 && height >= 16
            && width <= 4_096 && height <= 4_096
            && width * height <= 4_096 * 2_160
    }
}

public enum CaptureFrameRate: Int, Codable, CaseIterable, Sendable {
    case fps30 = 30
    case fps60 = 60
}

public struct CaptureAudioConfiguration: Codable, Equatable, Sendable {
    public var includeSystemAudio: Bool
    public var includeMicrophone: Bool

    public init(includeSystemAudio: Bool = true, includeMicrophone: Bool = true) {
        self.includeSystemAudio = includeSystemAudio
        self.includeMicrophone = includeMicrophone
    }
}

public struct CameraOverlayConfiguration: Codable, Equatable, Sendable {
    public enum Position: String, Codable, CaseIterable, Sendable {
        case topLeading
        case topTrailing
        case bottomLeading
        case bottomTrailing
    }

    public var deviceIdentifier: String
    public var position: Position
    /// Fraction of output width, constrained to 0.1 ... 0.5.
    public var widthFraction: Double

    public init(
        deviceIdentifier: String,
        position: Position = .bottomTrailing,
        widthFraction: Double = 0.2
    ) {
        self.deviceIdentifier = deviceIdentifier
        self.position = position
        self.widthFraction = widthFraction
    }
}

public struct CaptureConfiguration: Codable, Equatable, Sendable {
    public var source: CaptureSource
    public var outputSize: CaptureOutputSize
    public var frameRate: CaptureFrameRate
    public var showCursor: Bool
    public var highlightClicks: Bool
    public var audio: CaptureAudioConfiguration
    public var camera: CameraOverlayConfiguration?

    public init(
        source: CaptureSource,
        outputSize: CaptureOutputSize,
        frameRate: CaptureFrameRate = .fps30,
        showCursor: Bool = true,
        highlightClicks: Bool = false,
        audio: CaptureAudioConfiguration = .init(),
        camera: CameraOverlayConfiguration? = nil
    ) {
        self.source = source
        self.outputSize = outputSize
        self.frameRate = frameRate
        self.showCursor = showCursor
        self.highlightClicks = highlightClicks
        self.audio = audio
        self.camera = camera
    }

    public func validate() throws {
        guard outputSize.isAtMost4K else {
            throw ValidationError.invalidOutputSize(outputSize)
        }
        switch source {
        case .display(let id), .window(let id):
            guard id > 0 else { throw ValidationError.invalidSourceIdentifier }
        case .application(let bundleIdentifier):
            guard !bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError.invalidSourceIdentifier
            }
        case .region(let displayID, let rect):
            guard displayID > 0, rect.isValid else {
                throw ValidationError.invalidRegion
            }
        }
        if let camera {
            guard !camera.deviceIdentifier.isEmpty else {
                throw ValidationError.invalidCameraIdentifier
            }
            guard camera.widthFraction.isFinite,
                (0.1...0.5).contains(camera.widthFraction)
            else {
                throw ValidationError.invalidCameraWidthFraction(camera.widthFraction)
            }
        }
    }

    public enum ValidationError: Error, Equatable {
        case invalidOutputSize(CaptureOutputSize)
        case invalidSourceIdentifier
        case invalidRegion
        case invalidCameraIdentifier
        case invalidCameraWidthFraction(Double)
    }
}
