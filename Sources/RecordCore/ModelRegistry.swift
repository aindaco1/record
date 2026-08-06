import Foundation

/// Models Record understands and can verify locally before transcription.
public enum ParakeetModelID: String, Codable, CaseIterable, Sendable {
    case v2 = "parakeet-tdt-0.6b-v2-coreml"
    case v3 = "parakeet-tdt-0.6b-v3-coreml"

    public init(configurationValue: String) throws {
        switch configurationValue.lowercased() {
        case "v2", Self.v2.rawValue:
            self = .v2
        case "v3", Self.v3.rawValue:
            self = .v3
        default:
            throw ModelRegistryError.unknownModel(configurationValue)
        }
    }

    public enum ModelRegistryError: Error, Equatable, CustomStringConvertible {
        case unknownModel(String)

        public var description: String {
            switch self {
            case .unknownModel(let value):
                return "unknown local transcription model: \(value)"
            }
        }
    }
}
