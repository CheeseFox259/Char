import Foundation

/// Raw byte cursor shared by journal readers. Decoding starts only at a complete line.
struct JournalReadCursor {
    static let batchBytes = 512 * 1024
    static let maximumLineBytes = 16 * 1024 * 1024
    var offset: UInt64
    var identity: NSNumber?
    private var partial = Data()
    private var discarding = false
    private(set) var oversizedLines = 0

    init(offset: UInt64 = 0, identity: NSNumber? = nil) {
        self.offset = offset; self.identity = identity
    }
    mutating func read(_ url: URL, size: UInt64, identity nextIdentity: NSNumber?) throws -> [Data] {
        if size < offset || (identity != nil && identity != nextIdentity) {
            offset = 0; partial.removeAll(); discarding = false
        }
        identity = nextIdentity
        guard size > offset else { return [] }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        let bytes = try handle.read(upToCount: Int(min(UInt64(Self.batchBytes),size-offset))) ?? Data()
        offset += UInt64(bytes.count)
        var records: [Data] = []
        var start = bytes.startIndex
        while start < bytes.endIndex {
            let newline = bytes[start...].firstIndex(of: 10)
            let end = newline ?? bytes.endIndex
            if !discarding {
                if partial.count + (end-start) > Self.maximumLineBytes {
                    partial.removeAll(); discarding = true; oversizedLines += 1
                    // Report the bounded parser limitation without exposing content or paths.
                    FileHandle.standardError.write(Data("Char: journal record exceeds 16 MiB; skipped one oversized line.\n".utf8))
                } else { partial.append(contentsOf: bytes[start..<end]) }
            }
            if let newline {
                if !discarding && !partial.isEmpty { records.append(partial) }
                partial = Data(); discarding = false; start = newline+1
            } else { break }
        }
        return records
    }
}
