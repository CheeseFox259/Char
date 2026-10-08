import AppKit
import CharCore

/// One native playback owner: attention batches are serial, interaction is interruptible.
@MainActor final class CompanionAudio: NSObject, NSSoundDelegate {
    struct Request {
        let notices: [AttentionNotice]
        let resolve: () -> (NSSound, Float)?
        let isValid: (AttentionNotice) -> Bool
    }
    private var queue: [Request] = []
    private var active: NSSound?
    private(set) var isPlayingAttention = false
    private(set) var currentGroup: AttentionPresentationGroup?
    private var cache: [String: NSSound] = [:]
    private var times: [String: TimeInterval] = [:]
    func sound(at path: String) -> NSSound? {
        if let cached = cache[path] { return cached }
        guard let sound = NSSound(contentsOfFile: path, byReference: true) else { return nil }
        cache[path] = sound; return sound
    }
    func enqueue(_ requests: [Request]) {
        guard !requests.isEmpty else { return }
        queue += requests
        if !isPlayingAttention { endActive(); next() }
    }
    @discardableResult func interaction(id: String, sound: NSSound, volume: Float, cooldown: Double) -> Bool {
        guard !isPlayingAttention else { return true }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - (times[id] ?? -.infinity) >= cooldown else { return true }
        endActive()
        if start(sound, volume: volume) { times[id] = now; return true }
        return false
    }
    func stop() {
        queue.removeAll(); endActive()
        isPlayingAttention = false; currentGroup = nil; cache.removeAll(); times.removeAll()
    }
    private func next() {
        isPlayingAttention = false; currentGroup = nil
        while !queue.isEmpty {
            let request = queue.removeFirst()
            guard request.notices.contains(where: request.isValid), let (sound, volume) = request.resolve() else { continue }
            isPlayingAttention = true; currentGroup = request.notices.first?.group
            if start(sound, volume: volume) { return }
            if let fallback = NSSound(named: NSSound.Name("Ping")), start(fallback, volume: 1) { return }
            isPlayingAttention = false; currentGroup = nil
        }
    }
    private func endActive() {
        active?.delegate = nil; active?.stop(); active = nil
    }
    private func start(_ source: NSSound, volume: Float) -> Bool {
        // Every play has a distinct identity, so a late delegate callback from an
        // interrupted play cannot finish a newer play of the same cached file.
        guard let sound = source.copy() as? NSSound else { return false }
        sound.volume = volume; sound.delegate = self; active = sound
        if sound.play() { return true }
        endActive(); return false
    }
    nonisolated func sound(_ sound: NSSound, didFinishPlaying finished: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.active === sound else { return }
            self.active = nil
            if self.isPlayingAttention { self.next() }
        }
    }
}
