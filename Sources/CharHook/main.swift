import Foundation
import Darwin
import CharCore
import CharObservations

let input = FileHandle.standardInput.readDataToEndOfFile()
let encoded: Data?
if CommandLine.arguments.contains("--kimi") {
    encoded = NewAgentHooks.kimi(input).flatMap { try? JSONEncoder().encode($0) }
} else {
    let event: ObservationEvent?
    if CommandLine.arguments.contains("--deepseek") { event = NewAgentHooks.deepseek(input) }
    else if CommandLine.arguments.contains("--pi") { event = PiObservationClassifier.hook(input) }
    else if CommandLine.arguments.contains("--codex") { event = ObservationClassifier.codexHook(input) }
    else { event = ObservationClassifier.claudeHook(input) }
    encoded = event.flatMap { try? JSONEncoder().encode($0) }
}
guard let encoded else { exit(0) }

let environment = ProcessInfo.processInfo.environment
let defaultPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Char/harness-hooks.jsonl")
let destination = environment["CHAR_HOOK_EVENTS"].map { URL(fileURLWithPath: $0) } ?? defaultPath
do {
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                            withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
    let descriptor = open(destination.path, O_WRONLY | O_CREAT | O_APPEND, 0o600)
    guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    defer { close(descriptor) }
    guard flock(descriptor, LOCK_EX) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    defer { flock(descriptor, LOCK_UN) }
    var line = encoded
    line.append(10)
    try line.withUnsafeBytes { bytes in
        var offset = 0
        while offset < bytes.count {
            let count = write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
            if count <= 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            offset += count
        }
    }
} catch {
    FileHandle.standardError.write(Data("char-hook: could not append local event\n".utf8))
    exit(1)
}
