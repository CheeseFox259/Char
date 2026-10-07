import Foundation
import Darwin

let queue = DispatchQueue(label: "char.minimax.adapter")
let env = ProcessInfo.processInfo.environment
let config = (env["CHAR_PLUGIN_CONFIG"].flatMap { $0.data(using: .utf8) }.flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [String:String] ?? [:]
let workEnd = env["CHAR_WORK_END"] ?? ""
let surface = config["surface"] ?? (workEnd.hasSuffix(".desktop") ? "desktop" : "cli")
let home = env["HOME"] ?? NSHomeDirectory()
let root = (env["MINIMAX_DATA_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil:$0 } ?? home+"/.minimax"
let directory = root+"/v2/plugin-data/hooks/"+(config["pluginPackageName"] ?? "char-observer")
let spool = directory+"/events.ndjson"
let formatter = ISO8601DateFormatter()
formatter.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
let plainFormatter = ISO8601DateFormatter()
func output(_ frame: [String:Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: frame) { try? FileHandle.standardOutput.write(contentsOf: data+Data([10])) }
}

final class Monitor {
    struct Session { var pid: Int32?; var cwd: String; var touched: TimeInterval }
    var running = false
    var offset: UInt64 = 0
    var identity: String?
    var buffer = Data()
    var discarding = false
    var watches: [DispatchSourceFileSystemObject] = []
    var sweepTimer: DispatchSourceTimer?
    var sessions: [String:Session] = [:]
    var reading = false
    // Bounded root-state retention; eviction affects liveness inference only, not new events.
    let maxSessions = 4096
    func info() -> (UInt64,String)? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: spool), let size = attrs[.size] as? NSNumber,
              let inode = attrs[.systemFileNumber] as? NSNumber else { return nil }
        return (size.uint64Value,"\(attrs[.systemNumber] ?? ""):\(inode)")
    }
    func start() {
        guard !running else { return }; running = true
        let current = info(); offset = current?.0 ?? 0; identity = current?.1
        buffer.removeAll(keepingCapacity: false); discarding = false; arm(); scheduleDrain()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now()+5,repeating: 5,leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in self?.sweep() }; timer.resume(); sweepTimer = timer
    }
    func stop() {
        running = false; watches.forEach { $0.cancel() }; watches.removeAll()
        sweepTimer?.cancel(); sweepTimer = nil; buffer.removeAll(); sessions.removeAll()
    }
    func nearestDirectory() -> String {
        var candidate = directory
        while !FileManager.default.fileExists(atPath: candidate) {
            let parent = (candidate as NSString).deletingLastPathComponent
            if parent == candidate || parent.isEmpty { break }; candidate = parent
        }
        return candidate
    }
    func arm() {
        guard running else { return }
        watches.forEach { $0.cancel() }; watches.removeAll()
        let ancestor = nearestDirectory()
        for path in [ancestor,spool] {
            let fd = open(path,O_EVTONLY)
            guard fd >= 0 else { continue }
            let watcher = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,eventMask: [.write,.rename,.delete,.attrib],queue: queue)
            watcher.setCancelHandler { close(fd) }
            watcher.setEventHandler { [weak self] in
                guard let self, self.running else { return }
                self.arm(); self.scheduleDrain()
            }
            watcher.resume(); watches.append(watcher)
        }
        // Close the registration gap if a deeper directory appeared while arming.
        if nearestDirectory() != ancestor { arm() }
    }
    func scheduleDrain() {
        guard running, !reading else { return }; reading = true
        queue.async { [weak self] in
            guard let self else { return }; self.reading = false
            guard self.running else { return }; self.drain()
            if let current = self.info(), current.0 > self.offset { self.scheduleDrain() }
        }
    }
    func drain() {
        guard let current = info() else { return }
        if (identity != nil && identity != current.1) || current.0 < offset {
            offset = 0; buffer.removeAll(); discarding = false
        }
        identity = current.1
        guard current.0 > offset, let handle = FileHandle(forReadingAtPath: spool) else { return }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
            let data = try handle.read(upToCount: Int(min(524288,current.0-offset))) ?? Data()
            // Advance by bytes read, never by a decoded/re-encoded UTF-8 string.
            offset += UInt64(data.count)
            for byte in data {
                if byte == 10 {
                    if !discarding { consume(buffer) }
                    buffer.removeAll(keepingCapacity: true); discarding = false
                } else if !discarding {
                    if buffer.count >= 1_048_576 { buffer.removeAll(keepingCapacity: false); discarding = true }
                    else { buffer.append(byte) }
                }
            }
        } catch { }
    }
    func consume(_ line: Data) {
        guard let record = (try? JSONSerialization.jsonObject(with: line)) as? [String:Any],
              (record["v"] as? Int) == 1, record["surface"] as? String == surface,
              let id = record["sid"] as? String, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, id.count <= 1024 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if sessions[id] == nil && sessions.count >= maxSessions,
           let oldest = sessions.min(by: { $0.value.touched < $1.value.touched })?.key { sessions.removeValue(forKey: oldest) }
        let pidValue = record["pid"] as? Int
        let pid = pidValue.flatMap { $0 > 1 && $0 <= Int(Int32.max) ? Int32($0):nil }
        let cwd = (record["cwd"] as? String).flatMap { $0.isEmpty ? nil:$0 } ?? sessions[id]?.cwd ?? ""
        sessions[id] = Session(pid: pid ?? sessions[id]?.pid,cwd: cwd,touched: now)
        guard let signal = record["signal"] as? String else { return }
        let state: String, reason: String?
        switch signal {
        case "running": state = "running"; reason = nil
        case "approval","question","turnEnded": state = "stopped"; reason = signal
        case "closed": state = "closed"; reason = nil
        default: return
        }
        let ts = record["ts"] as? String ?? ""
        let time = formatter.date(from: ts) ?? plainFormatter.date(from: ts) ?? Date()
        var event: [String:Any] = ["workEnd":workEnd,"nativeID":id.trimmingCharacters(in: .whitespacesAndNewlines),"timestamp":formatter.string(from: time),"state":state]
        if let reason { event["reason"] = reason }
        var target: [String:Any] = [:]
        if let pid { target["processID"] = Int(pid) }; if !cwd.isEmpty { target["sourcePath"] = cwd }
        if !target.isEmpty { event["target"] = target }
        output(["version":1,"event":event])
        if state == "closed" { sessions.removeValue(forKey: id) }
    }
    func sweep() {
        for (id,session) in sessions {
            guard let pid = session.pid, kill(pid,0) != 0, errno != EPERM else { continue }
            var event: [String:Any] = ["workEnd":workEnd,"nativeID":id,"timestamp":formatter.string(from: Date()),"state":"closed"]
            if !session.cwd.isEmpty { event["target"] = ["processID":Int(pid),"sourcePath":session.cwd] }
            output(["version":1,"event":event]); sessions.removeValue(forKey: id)
        }
    }
}
let monitor = Monitor()
let helperQueue = DispatchQueue(label: "char.minimax.helper")
var pendingHelpers = 0
var stdinClosed = false
func finishWhenDrained() {
    if stdinClosed && pendingHelpers == 0 { monitor.stop(); cancelChild(); exit(0) }
}
let childLock = NSLock()
var child: Process?
func cancelChild() { childLock.lock(); let current = child; childLock.unlock(); if current?.isRunning == true { current?.terminate() } }

func delegate(_ request: [String:Any]) throws -> [String:Any] {
    let process = Process(), input = Pipe(), outputPipe = Pipe()
    let package = env["CHAR_PLUGIN_DIRECTORY"] ?? FileManager.default.currentDirectoryPath
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node",package+"/adapter/adapter.mjs"]
    process.environment = env; process.currentDirectoryURL = URL(fileURLWithPath: package)
    process.standardInput = input; process.standardOutput = outputPipe; process.standardError = FileHandle.nullDevice
    childLock.lock(); child = process; childLock.unlock()
    defer { childLock.lock(); child = nil; childLock.unlock(); if process.isRunning { process.terminate() } }
    try process.run()
    outputPipe.fileHandleForWriting.closeFile()
    let maintenance = ["install","update","uninstall"].contains(request["method"] as? String ?? "")
    let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now()+(maintenance ? 14:2.6),execute: timeout)
    defer { timeout.cancel() }
    try input.fileHandleForWriting.write(contentsOf: JSONSerialization.data(withJSONObject: request)+Data([10]))
    try input.fileHandleForWriting.close()
    var response = Data()
    while let bytes = try outputPipe.fileHandleForReading.read(upToCount: 4096), !bytes.isEmpty {
        response.append(bytes)
        if response.count > 1_048_576 { throw NSError(domain:"adapter",code:1,userInfo:[NSLocalizedDescriptionKey:"helper response exceeds limit"]) }
    }
    process.waitUntilExit()
    guard process.terminationStatus == 0,
          let line = response.split(separator:10).last,
          let result = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String:Any],
          result["id"] as? String == request["id"] as? String else {
        throw NSError(domain:"adapter",code:2,userInfo:[NSLocalizedDescriptionKey:"Node helper unavailable, timed out or returned an invalid response"])
    }
    return result
}
func handle(_ data: Data) {
    let request = (try? JSONSerialization.jsonObject(with: data)) as? [String:Any] ?? [:]
    let id: Any = request["id"] as? String ?? NSNull()
    guard request["version"] as? Int == 1, let method = request["method"] as? String else {
        output(["version":1,"id":id,"error":"unsupported protocol request"]); return
    }
    switch method {
    case "hello": output(["version":1,"id":id,"result":["protocolVersion":1]])
    case "start": monitor.start(); output(["version":1,"id":id,"result":[:]])
    case "stop": monitor.stop(); output(["version":1,"id":id,"result":[:]])
    case "inspect","visit","install","update","uninstall":
        pendingHelpers += 1
        helperQueue.async {
            let response: [String:Any]
            do { response = try delegate(request) }
            catch { response = ["version":1,"id":id,"error":error.localizedDescription] }
            queue.async {
                output(response); pendingHelpers -= 1; finishWhenDrained()
            }
        }
    default: output(["version":1,"id":id,"error":"unknown method: \(method)"])
    }
}
_ = signal(SIGPIPE,SIG_IGN)
_ = signal(SIGTERM,SIG_IGN); _ = signal(SIGINT,SIG_IGN)
let termination = [SIGTERM,SIGINT].map { code -> DispatchSourceSignal in
    let source = DispatchSource.makeSignalSource(signal: code,queue: .global())
    source.setEventHandler { cancelChild(); exit(0) }; source.resume(); return source
}
DispatchQueue.global().async {
    var input = Data()
    var chunk = [UInt8](repeating: 0,count: 4096)
    while true {
        let count = read(STDIN_FILENO,&chunk,chunk.count)
        if count <= 0 { break }
        input.append(contentsOf: chunk.prefix(count))
        if input.count > 1_048_576 { cancelChild(); exit(1) }
        while let newline = input.firstIndex(of:10) {
            let line = Data(input[..<newline]); input.removeSubrange(...newline)
            if !line.isEmpty { queue.async { handle(line) } }
        }
    }
    // Drain admitted requests before EOF shutdown; an in-flight inspect must answer.
    queue.async { stdinClosed = true; finishWhenDrained() }
}
dispatchMain()
