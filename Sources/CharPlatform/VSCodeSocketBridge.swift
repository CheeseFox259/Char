import Darwin
import Foundation

@MainActor public final class VSCodeSocketBridge: VSCodeControlling {
    private struct Request: Encodable { let op: String; let token: String? }
    private struct Response: Decodable { let ok: Bool; let token: String? }
    private struct BridgeToken: Codable { let socketName: String; let token: String }

    public init() {}

    private var directory: URL {
        URL(fileURLWithPath: "/tmp/char-vscode-\(getuid())", isDirectory: true)
    }

    private func directoryIsPrivate() -> Bool {
        var info = stat()
        return lstat(directory.path, &info) == 0 &&
            (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) &&
            info.st_uid == getuid() && (info.st_mode & 0o077) == 0
    }

    private func sockets() -> [URL] {
        guard directoryIsPrivate() else { return [] }
        return (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix("bridge-") && $0.pathExtension == "sock" } ?? []
    }

    private func request(_ request: Request, at socketURL: URL) -> Response? {
        guard directoryIsPrivate(),
              socketURL.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
              socketURL.lastPathComponent.hasPrefix("bridge-"),
              socketURL.pathExtension == "sock",
              let payload = try? JSONEncoder().encode(request) else { return nil }
        let path = socketURL.path
        let bytes = Array(path.utf8CString)
        var address = sockaddr_un()
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes.map { UInt8(bitPattern: $0) })
        }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }
        var timeout = timeval(tv_sec: 0, tv_usec: 300_000)
        _ = withUnsafePointer(to: &timeout) {
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
        }
        _ = withUnsafePointer(to: &timeout) {
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return nil }
        let output = payload + Data([10])
        let sent = output.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, output.count) }
        guard sent == output.count else { return nil }
        var input = Data()
        var byte: UInt8 = 0
        while input.count < 4096 {
            let count = Darwin.read(fd, &byte, 1)
            guard count == 1 else { return nil }
            if byte == 10 { break }
            input.append(byte)
        }
        return try? JSONDecoder().decode(Response.self, from: input)
    }

    private func decode(_ value: String) -> (URL, String)? {
        guard let data = Data(base64Encoded: value),
              let token = try? JSONDecoder().decode(BridgeToken.self, from: data),
              token.socketName.hasPrefix("bridge-"),
              token.socketName.hasSuffix(".sock"),
              !token.socketName.contains("/") else { return nil }
        return (directory.appendingPathComponent(token.socketName), token.token)
    }

    public func captureFocusedTab() -> String? {
        let candidates = sockets().compactMap { socketURL -> String? in
            guard let reply = request(Request(op: "capture", token: nil), at: socketURL),
                  reply.ok, let token = reply.token else { return nil }
            let encoded = BridgeToken(socketName: socketURL.lastPathComponent, token: token)
            return (try? JSONEncoder().encode(encoded))?.base64EncodedString()
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    public func contains(token: String) -> Bool? {
        guard let (socketURL, id) = decode(token) else { return false }
        // A removed socket confirms that this extension instance ended. A timeout does not.
        var info = stat()
        if lstat(socketURL.path, &info) != 0 && errno == ENOENT { return false }
        return request(Request(op: "contains", token: id), at: socketURL)?.ok
    }

    public func focus(token: String) -> Bool {
        guard let (socketURL, id) = decode(token) else { return false }
        return request(Request(op: "focus", token: id), at: socketURL)?.ok == true
    }

    public func isActive(token: String) -> Bool {
        guard let (socketURL, id) = decode(token) else { return false }
        return request(Request(op: "isActive", token: id), at: socketURL)?.ok == true
    }
}
