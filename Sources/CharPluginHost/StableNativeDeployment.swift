import Foundation

public enum StableNativeDeployment {
    /// Bundled files are deployed atomically; client configs only reference this stable root.
    public static func prepare(bundle: URL, support: URL) throws -> [String: String] {
        let support = support.resolvingSymlinksInPath()
        let fm = FileManager.default
        let destination = support.appendingPathComponent("runtime", isDirectory: true)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let binary = bundle.appendingPathComponent("Contents/MacOS/char-hook")
        let deployed = destination.appendingPathComponent("char-hook")
        try copy(binary, to: deployed, executable: true)
        let native = bundle.appendingPathComponent("Contents/Resources/NativeIntegrations", isDirectory: true)
        let scripts = destination.appendingPathComponent("native-integrations", isDirectory: true)
        if let files = fm.enumerator(at: native, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let file as URL in files where (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                let relative = String(file.path.dropFirst(native.path.count + 1))
                let target = scripts.appendingPathComponent(relative)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try copy(file, to: target, executable: false)
            }
        }
        let user = ProcessInfo.processInfo.environment
        var environment = ["PATH": "/opt/homebrew/bin:/usr/local/bin:" + (user["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"),
                           "HOME": fm.homeDirectoryForCurrentUser.path,
                           "CHAR_HOOK_BINARY": deployed.path,
                           "CHAR_HOOK_EVENTS": user["CHAR_HOOK_EVENTS"] ?? support.appendingPathComponent("harness-hooks.jsonl").path,
                           "CHAR_NATIVE_ROOT": scripts.path,
                           "CHAR_SUPPORT_DIRECTORY": support.path]
        if let root = user["KIMI_CODE_HOME"] { environment["KIMI_CODE_HOME"] = root }
        return environment
    }
    private static func copy(_ source: URL, to destination: URL, executable: Bool) throws {
        let data = try Data(contentsOf: source)
        if (try? Data(contentsOf: destination)) != data { try data.write(to: destination, options: .atomic) }
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o700 : 0o600], ofItemAtPath: destination.path)
    }
}
