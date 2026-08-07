import AVFoundation
import Foundation
import RecordCore

/// Container-level recovery inspection only. It does not decode, rewrite, or
/// upload media, and it deliberately keeps content out of diagnostics.
enum SessionMediaInspector {
    static func inspect(_ url: URL) throws -> SessionRecovery.MediaInspection {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber, size.int64Value > 0 else {
            return .empty
        }

        switch url.pathExtension.lowercased() {
        case "caf":
            do {
                let file = try AVAudioFile(forReading: url)
                return file.length > 0 ? .playable : .empty
            } catch {
                return .corrupt
            }
        case "mov":
            do {
                let reader = try AVAssetReader(asset: AVURLAsset(url: url))
                return reader.status == .failed ? .corrupt : .playable
            } catch {
                return .corrupt
            }
        default:
            return .corrupt
        }
    }
}
