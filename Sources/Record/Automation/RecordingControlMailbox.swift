import Darwin
import Foundation
import RecordCore

/// Local IPC between two invocations of the same sandboxed Record executable.
/// Only fixed files in its private cache are used; no socket, URL handler, app
/// group, new entitlement, arbitrary path, or general payload is exposed.
struct RecordingControlMailbox: Sendable {
    struct Endpoint: Codable, Sendable {
        let instance: UUID
    }

    enum MailboxError: Error, LocalizedError {
        case unavailable, busy, unconfirmed, invalidFile
        var errorDescription: String? {
            switch self {
            case .unavailable: "Open Record before using recording commands."
            case .busy: "Another recording command is still running. Try again shortly."
            case .unconfirmed: "Record did not confirm this command. Check status before retrying."
            case .invalidFile:
                "Record’s local command channel is unavailable. Quit and reopen Record."
            }
        }
    }

    final class Lock {
        private let descriptor: Int32
        init(descriptor: Int32) { self.descriptor = descriptor }
        deinit { flock(descriptor, LOCK_UN); close(descriptor) }
    }

    let directory: URL
    static let byteLimit = 2_048

    init(directory: URL? = nil) throws {
        let cache = try FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        self.directory =
            directory
            ?? cache.resolvingSymlinksInPath()
            .appendingPathComponent("RecordControl-v1", isDirectory: true)
        guard mkdir(self.directory.path, 0o700) == 0 || errno == EEXIST else {
            throw MailboxError.invalidFile
        }
        let values = try self.directory.resourceValues(forKeys: [
            .isDirectoryKey, .isSymbolicLinkKey,
        ])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw MailboxError.invalidFile
        }
        var info = stat()
        guard lstat(self.directory.path, &info) == 0, info.st_uid == geteuid(),
            info.st_mode & 0o077 == 0
        else { throw MailboxError.invalidFile }
    }

    func acquire(_ name: String) throws -> Lock {
        let fd = open(
            directory.appendingPathComponent(name + ".lock").path,
            O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw MailboxError.invalidFile }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
            info.st_uid == geteuid(), info.st_nlink == 1
        else { close(fd); throw MailboxError.invalidFile }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd); throw MailboxError.busy
        }
        return Lock(descriptor: fd)
    }

    func read<T: Decodable>(_ type: T.Type, name: String) throws -> T {
        let fd = open(
            directory.appendingPathComponent(name).path,
            O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw MailboxError.unavailable }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
            info.st_uid == geteuid(), info.st_nlink == 1,
            info.st_size > 0, info.st_size <= Self.byteLimit
        else { throw MailboxError.invalidFile }
        var bytes = [UInt8](repeating: 0, count: Self.byteLimit + 1)
        let count = Darwin.read(fd, &bytes, bytes.count)
        guard count > 0, count <= Self.byteLimit else { throw MailboxError.invalidFile }
        return try JSONDecoder().decode(type, from: Data(bytes.prefix(count)))
    }

    func write<T: Encodable>(_ value: T, name: String) throws {
        let bytes = try JSONEncoder().encode(value)
        guard bytes.count <= Self.byteLimit else { throw MailboxError.invalidFile }
        try bytes.write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    /// The caller holds the client lock until it receives a matching response.
    /// A response confirms acceptance; capture completion is reported by status.
    func send(action: RecordingControl.Action, mode: RecordingControl.Mode?) throws
        -> RecordingControl.Response
    {
        let lock = try acquire("client")
        defer { withExtendedLifetime(lock) {} }
        // A readable stale endpoint never proves that an app is running.
        do {
            let abandoned = try acquire("server")
            withExtendedLifetime(abandoned) {}
            throw MailboxError.unavailable
        } catch MailboxError.busy { /* The live app owns the server lock. */  }
        let endpoint = try read(Endpoint.self, name: "endpoint.json")
        let request = RecordingControl.Request(
            instance: endpoint.instance, action: action, mode: mode)
        try write(request, name: "request.json")
        let deadline = ProcessInfo.processInfo.systemUptime + 4
        while ProcessInfo.processInfo.systemUptime < deadline {
            if let reply = try? read(RecordingControl.Response.self, name: "response.json"),
                reply.id == request.id
            {
                return reply
            }
            Thread.sleep(forTimeInterval: 0.025)
        }
        throw MailboxError.unconfirmed
    }
}

@MainActor
final class RecordingControlServer {
    private let mailbox: RecordingControlMailbox
    private var ownership: RecordingControlMailbox.Lock?
    private var instance = UUID()
    private var source: DispatchSourceFileSystemObject?
    private var lastRequest: UUID?
    private var handler: ((RecordingControl.Request) -> RecordingControl.Response)?

    init(mailbox: RecordingControlMailbox? = nil) throws {
        let mailbox = try mailbox ?? RecordingControlMailbox()
        self.mailbox = mailbox
        ownership = try mailbox.acquire("server")
    }

    func start(handler: @escaping (RecordingControl.Request) -> RecordingControl.Response) throws {
        self.handler = handler
        try resume()
    }

    /// Permission relaunch opens a new app before the old process exits. Hand
    /// ownership over explicitly so that the replacement can initialize.
    func suspend() {
        source?.cancel()
        source = nil
        ownership = nil
    }

    func resume() throws {
        guard source == nil else { return }
        if ownership == nil { ownership = try mailbox.acquire("server") }
        instance = UUID()
        lastRequest = nil
        let descriptor = open(mailbox.directory.path, O_EVTONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw RecordingControlMailbox.MailboxError.invalidFile }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write], queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.receive() } }
        source.setCancelHandler { close(descriptor) }
        self.source = source
        source.resume()
        try mailbox.write(
            RecordingControlMailbox.Endpoint(instance: instance),
            name: "endpoint.json")
    }

    private func receive() {
        guard ownership != nil,
            let request = try? mailbox.read(RecordingControl.Request.self, name: "request.json"),
            request.id != lastRequest
        else { return }
        lastRequest = request.id
        // Reject stale or malformed commands before any UI/capture side effect.
        let response: RecordingControl.Response
        do {
            try request.validate(instance: instance)
            guard let handler else { return }
            response = handler(request)
        } catch {
            response = .init(
                id: request.id, snapshot: .init(phase: .idle),
                failure: (error as? RecordingControl.Failure) ?? .invalidCommand)
        }
        try? mailbox.write(response, name: "response.json")
    }

    deinit { source?.cancel() }
}
