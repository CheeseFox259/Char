import Foundation
import Darwin

/// Directory entries change independently of journal contents. Reuse entries while
/// each directory's identity/mtime/ctime is unchanged; append cursors still stat
/// every known journal on each poll. New nested directories are visited immediately.
final class JournalDirectoryIndex {
    private struct Revision: Equatable {
        let inode: UInt64
        let modifiedSeconds: Int
        let modifiedNanos: Int
        let changedSeconds: Int
        let changedNanos: Int
    }
    private struct Node {
        let revision: Revision
        let directories: [URL]
        let files: [URL]
    }
    private let root: URL
    private let includes: (URL) -> Bool
    private var nodes: [String: Node] = [:]
    init(root: URL, includes: @escaping (URL) -> Bool) {
        self.root = root; self.includes = includes
    }
    func files() -> [URL] {
        var visited = Set<String>()
        let result = visit(root, visited: &visited)
        nodes = nodes.filter { visited.contains($0.key) }
        return result.sorted { $0.path < $1.path }
    }
    private func visit(_ directory: URL, visited: inout Set<String>) -> [URL] {
        guard let revision = revision(directory) else { return [] }
        visited.insert(directory.path)
        let node: Node
        if let previous = nodes[directory.path], previous.revision == revision {
            node = previous
        } else {
            guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                                                              options: [.skipsHiddenFiles]) else { return [] }
            var directories: [URL] = [], files: [URL] = []
            for entry in entries {
                var value = stat()
                let result = entry.withUnsafeFileSystemRepresentation { path -> Int32 in
                    guard let path else { return -1 }
                    return lstat(path, &value)
                }
                guard result == 0 else { continue }
                if value.st_mode & S_IFMT == S_IFDIR { directories.append(entry) }
                else if includes(entry) { files.append(entry) }
            }
            node = Node(revision: revision, directories: directories, files: files)
            nodes[directory.path] = node
        }
        var files = node.files
        for child in node.directories { files.append(contentsOf: visit(child, visited: &visited)) }
        return files
    }
    private func revision(_ directory: URL) -> Revision? {
        var value = stat()
        let result = directory.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return stat(path, &value)
        }
        guard result == 0, value.st_mode & S_IFMT == S_IFDIR else { return nil }
        return Revision(inode: UInt64(value.st_ino), modifiedSeconds: value.st_mtimespec.tv_sec,
                        modifiedNanos: value.st_mtimespec.tv_nsec, changedSeconds: value.st_ctimespec.tv_sec,
                        changedNanos: value.st_ctimespec.tv_nsec)
    }
}
