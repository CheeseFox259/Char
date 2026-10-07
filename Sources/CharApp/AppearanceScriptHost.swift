import Foundation
import CharPlatform

/// One selected appearance, one persistent helper, serial requests off the UI thread.
final class AppearanceScriptHost: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Char.appearance-script", qos: .utility)
    private let process = Process()
    private let input = Pipe(), output = Pipe()
    private var sequence = 0
    private let admissionLock = NSLock()
    private var pending = 0
    private func reserve() -> Bool {
        admissionLock.lock(); defer { admissionLock.unlock() }
        guard pending < 32 else { return false }; pending += 1; return true
    }
    private func release() { admissionLock.lock(); pending -= 1; admissionLock.unlock() }
    private var initialized = false
    private let source: String
    init(executable: URL, source: String) throws {
        self.source = source
        process.executableURL = executable
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        // Suppress SIGPIPE on this pipe only; a dead helper reports a Swift write error.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor,F_SETNOSIGPIPE,1)
        try process.run()
        // Parent must not retain the helper's write end: EOF is observable after exit.
        output.fileHandleForWriting.closeFile()
    }
    func stop() { if process.isRunning { process.terminate() } }
    deinit { stop() }
    func event(_ data: [String: String]) async throws -> [PetSkinAction] {
        guard reserve() else { stop(); throw PetSkinError.invalid("appearance script event queue full") }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                defer { self.release() }
                do {
                    let until = ProcessInfo.processInfo.systemUptime+0.5
                    if !self.initialized { _ = try self.request(["method":"init", "source": self.source],until: until); self.initialized = true }
                    let result = try self.request(["method":"event", "event": data],until: until)
                    guard let actions = result["actions"], JSONSerialization.isValidJSONObject(actions) else { throw PetSkinError.invalid("script actions must be an array") }
                    let decoded = try JSONDecoder().decode([PetSkinAction].self, from: JSONSerialization.data(withJSONObject: actions))
                    guard decoded.count <= 16 else { throw PetSkinError.invalid("script returned more than 16 actions") }
                    continuation.resume(returning: decoded)
                } catch { self.stop(); continuation.resume(throwing: error) }
            }
        }
    }
    private func request(_ fields: [String:Any], until: TimeInterval) throws -> [String:Any] {
        guard process.isRunning else { throw PetSkinError.invalid("appearance script stopped") }
        sequence += 1; var message = fields; message["id"] = sequence
        let remaining = until-ProcessInfo.processInfo.systemUptime
        guard remaining > 0 else { throw PetSkinError.invalid("appearance script timed out") }
        let deadline = DispatchWorkItem { [weak self] in self?.stop() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now()+remaining,execute: deadline)
        defer { deadline.cancel() }
        try input.fileHandleForWriting.write(contentsOf: JSONSerialization.data(withJSONObject: message)+Data([10]))
        var reply = Data()
        while reply.count <= 32_768 {
            guard let next = try output.fileHandleForReading.read(upToCount: 1), !next.isEmpty else { throw PetSkinError.invalid("appearance script timed out or exited") }
            if next[0] == 10 { break }; reply.append(next)
        }
        guard reply.count <= 32_768, let result = try JSONSerialization.jsonObject(with: reply) as? [String:Any], result["id"] as? Int == sequence else { throw PetSkinError.invalid("invalid script reply") }
        if let error = result["error"] as? String { throw PetSkinError.invalid(error) }
        return result
    }
}

actor AppearanceIconWorker {
    static let shared = AppearanceIconWorker()
    func synchronize(app: URL, png: Data?, archive: URL) throws {
        guard !Task.isCancelled else { return }
        try InstalledAppearanceIcon.synchronize(app: app,png: png,archiveDirectory: archive)
    }
}
