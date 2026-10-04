import Foundation

/// Commands describe the desired state, never a toggle. Adapters snapshot the
/// existing capture owner; this policy does not maintain a second recorder.
public enum RecordingControl {
    public enum Action: String, Codable, CaseIterable, Sendable {
        case start, stop, pause, resume, status
    }

    public enum Mode: String, Codable, CaseIterable, Sendable {
        case screen, audio, dictation

        public func audioConfiguration(using saved: CaptureAudioConfiguration)
            -> CaptureAudioConfiguration
        {
            var audio = saved
            if self == .dictation {
                audio.includeMicrophone = true
                audio.includeSystemAudio = false
            }
            return audio
        }
    }

    public enum Phase: String, Codable, CaseIterable, Sendable {
        case idle, preparing, recording, pausing, paused, resuming, stopping, saving
    }

    public struct Snapshot: Codable, Equatable, Sendable {
        public let phase: Phase
        public let mode: Mode?
        public init(phase: Phase, mode: Mode? = nil) {
            self.phase = phase
            self.mode = mode
        }
    }

    public enum Failure: String, Codable, Error, Sendable {
        case busy, unsupported, invalidCommand, setupRequired, unavailable, expired
    }

    public enum Effect: Equatable, Sendable {
        case none, start(Mode), stop, pause, resume
    }

    public static func effect(
        for action: Action, mode: Mode?, in state: Snapshot
    ) throws -> Effect {
        guard (action == .start) == (mode != nil) else { throw Failure.invalidCommand }
        switch action {
        case .status: return .none
        case .start:
            guard let mode else { throw Failure.invalidCommand }
            if state.phase == .idle { return .start(mode) }
            if state.mode == mode,
                [.preparing, .recording, .paused, .pausing, .resuming].contains(state.phase)
            {
                return .none
            }
            throw Failure.busy
        case .stop:
            switch state.phase {
            case .idle, .stopping, .saving: return .none
            default: return .stop
            }
        case .pause, .resume:
            guard state.mode == .screen else { throw Failure.unsupported }
            switch (action, state.phase) {
            case (.pause, .paused), (.pause, .pausing),
                (.resume, .recording), (.resume, .resuming):
                return .none
            case (.pause, .recording): return .pause
            case (.resume, .paused): return .resume
            default: throw Failure.busy
            }
        }
    }

    /// The local mailbox carries only closed commands and coarse state, never
    /// paths, transcripts, device names, configuration, or executable arguments.
    public struct Request: Codable, Equatable, Sendable {
        public let version: Int
        public let id: UUID
        public let instance: UUID
        public let expiresAt: Date
        public let action: Action
        public let mode: Mode?

        public init(
            instance: UUID, action: Action, mode: Mode? = nil,
            now: Date = Date(), id: UUID = UUID()
        ) {
            version = 1
            self.id = id
            self.instance = instance
            expiresAt = now.addingTimeInterval(5)
            self.action = action
            self.mode = mode
        }

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case version, id, instance, expiresAt, action, mode
        }

        private struct Field: CodingKey {
            let stringValue: String
            var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }

        public init(from decoder: any Decoder) throws {
            let fields = try decoder.container(keyedBy: Field.self).allKeys.map(\.stringValue)
            guard Set(fields).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))) else {
                throw Failure.invalidCommand
            }
            let values = try decoder.container(keyedBy: CodingKeys.self)
            version = try values.decode(Int.self, forKey: .version)
            id = try values.decode(UUID.self, forKey: .id)
            instance = try values.decode(UUID.self, forKey: .instance)
            expiresAt = try values.decode(Date.self, forKey: .expiresAt)
            action = try values.decode(Action.self, forKey: .action)
            mode = try values.decodeIfPresent(Mode.self, forKey: .mode)
        }

        public func validate(instance: UUID, now: Date = Date()) throws {
            guard version == 1, self.instance == instance,
                (action == .start) == (mode != nil)
            else { throw Failure.invalidCommand }
            guard expiresAt > now, expiresAt.timeIntervalSince(now) <= 5.5 else {
                throw Failure.expired
            }
        }
    }

    public struct Response: Codable, Equatable, Sendable {
        public let id: UUID
        public let snapshot: Snapshot
        public let failure: Failure?
        public init(id: UUID, snapshot: Snapshot, failure: Failure? = nil) {
            self.id = id
            self.snapshot = snapshot
            self.failure = failure
        }
    }
}
