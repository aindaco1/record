import ArgumentParser
import Foundation
import RecordCore

extension RecordingControl.Action: ExpressibleByArgument {}
extension RecordingControl.Mode: ExpressibleByArgument {}

struct ControlRecording: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "control",
        abstract: "Control the running Record app without starting a second recorder.",
        discussion:
            "Start uses Record’s saved source and audio settings. Dictation captures only the selected microphone. Pause and resume apply to screen recordings. Commands confirm acceptance; use status to check completion. Example: record control start --mode audio"
    )

    @Argument(help: "Desired action: start, stop, pause, resume, or status.")
    var action: RecordingControl.Action

    @Option(name: .long, help: "Required for start: screen, audio, or dictation.")
    var mode: RecordingControl.Mode?

    @Flag(
        name: .long,
        help: "Print a JSON response containing only command ID, state, mode, and any error.")
    var json = false

    mutating func validate() throws {
        guard (action == .start) == (mode != nil) else {
            throw ValidationError("Use --mode with start only: screen, audio, or dictation.")
        }
    }

    func run() throws {
        let response = try RecordingControlMailbox().send(action: action, mode: mode)
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            print(String(decoding: try encoder.encode(response), as: UTF8.self))
        } else {
            print(
                response.snapshot.phase.rawValue
                    + (response.snapshot.mode.map { " · " + $0.rawValue } ?? ""))
        }
        if let failure = response.failure {
            FileHandle.standardError.write(Data((Self.message(for: failure) + "\n").utf8))
            throw ExitCode.failure
        }
    }

    static func message(for failure: RecordingControl.Failure) -> String {
        switch failure {
        case .busy: "Record is busy with another capture or transition. Check status and try again."
        case .unsupported: "Pause and resume require a screen recording."
        case .invalidCommand:
            "The recording command is invalid or belongs to an older app instance."
        case .setupRequired:
            "Complete recording permissions, source selection, and model setup in Record first."
        case .unavailable:
            "Record could not start this operation. Check its settings and try again."
        case .expired: "The command expired without running. Check status and try again."
        }
    }
}
