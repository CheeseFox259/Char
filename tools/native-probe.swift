// A noninteractive feasibility probe for issue #3. It never activates apps or reads app content.
import ApplicationServices
import Foundation

struct CommandResult {
    let status: Int32
    let output: String
}

func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return CommandResult(status: process.terminationStatus,
                         output: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
}

func executable(_ name: String) -> String? {
    let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
    return paths.map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
}

func schemes(at path: String) -> [String] {
    guard let bundle = Bundle(path: path),
          let types = bundle.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] else { return [] }
    return types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }.sorted()
}

func report() {
    print("Accessibility trusted: \(AXIsProcessTrusted())")
    print("tmux executable: \(executable("tmux") ?? "absent")")
    print("warpctrl executable: \(executable("warpctrl") ?? "absent")")

    let applications: [(String, String, String?)] = [
        ("Warp", "/Applications/Warp.app", "Contents/Resources/bundled/skills/warpctrl/SKILL.md"),
        ("Codex Desktop", "/Applications/ChatGPT.app", nil),
        ("Tabbit", "/Applications/Tabbit.app", "Contents/Resources/scripting.sdef"),
        ("WeChat", "/Applications/WeChat.app", "Contents/Resources/scripting.sdef"),
        ("VS Code", "/Applications/Visual Studio Code.app", "Contents/Resources/scripting.sdef"),
    ]
    for (name, path, resource) in applications {
        guard let bundle = Bundle(path: path) else {
            print("\(name): absent")
            continue
        }
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        print("\(name): version=\(version), bundle=\(bundle.bundleIdentifier ?? "unknown"), schemes=\(schemes(at: path).joined(separator: ","))")
        if let resource {
            print("\(name) bundled \(URL(fileURLWithPath: resource).lastPathComponent): \(FileManager.default.fileExists(atPath: path + "/" + resource))")
        }
    }
    print("Capability metadata only; no exact app navigation or return path is established by this report.")
}

func tmuxFixture() throws {
    guard let tmux = executable("tmux") else { throw NSError(domain: "probe", code: 1, userInfo: [NSLocalizedDescriptionKey: "tmux absent"]) }
    let socket = "char-probe-\(UUID().uuidString)"
    func call(_ arguments: [String]) throws -> String {
        let result = try run(tmux, ["-L", socket] + arguments)
        guard result.status == 0 else {
            throw NSError(domain: "probe", code: Int(result.status), userInfo: [NSLocalizedDescriptionKey: "tmux \(arguments.joined(separator: " ")): \(result.output)"])
        }
        return result.output
    }
    defer { _ = try? call(["kill-server"]) }
    _ = try call(["new-session", "-d", "-s", "fixture", "sleep 30"])
    let first = try call(["display-message", "-p", "-t", "fixture:0.0", "#{pane_id}"])
    let second = try call(["split-window", "-d", "-P", "-F", "#{pane_id}", "-t", first, "sleep 30"])
    _ = try call(["select-pane", "-t", second])
    let active = try call(["display-message", "-p", "-t", "fixture:0", "#{pane_id}"])
    guard active == second else {
        throw NSError(domain: "probe", code: 2, userInfo: [NSLocalizedDescriptionKey: "selected pane \(active), expected \(second)"])
    }
    print("Isolated tmux pane selection: PASS (first=\(first), selected=\(second), active=\(active))")
    print("This does not focus a Warp tab or establish reattachment after tab closure.")
}

do {
    switch Array(CommandLine.arguments.dropFirst()) {
    case [], ["--report"]: report()
    case ["--tmux-fixture"]: try tmuxFixture()
    default:
        fputs("Usage: native-probe [--report|--tmux-fixture]\n", stderr)
        exit(2)
    }
} catch {
    fputs("Probe failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
