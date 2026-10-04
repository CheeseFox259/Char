import AppKit
import QuartzCore

/// [DEBUG-char-wheel-deep] Temporary, opt-in boundary trace; contains geometry only.
@MainActor final class WheelDiagnostics {
    private let enabled = ProcessInfo.processInfo.environment["CHAR_WHEEL_DIAGNOSTICS"] == "1"
    private var sequence = 0
    private var active: (sequence: Int, until: TimeInterval, layer: CALayer)?
    func input(_ event: NSEvent, offset: Int) -> Int {
        guard enabled else { return 0 }
        sequence += 1
        var data: [String: Any] = ["kind": "input", "sequence": sequence, "eventTime": event.timestamp,
            "now": ProcessInfo.processInfo.systemUptime, "dx": event.scrollingDeltaX, "dy": event.scrollingDeltaY,
            "precise": event.hasPreciseScrollingDeltas, "phase": event.phase.rawValue, "momentum": event.momentumPhase.rawValue, "offset": offset]
        if let cg = event.cgEvent {
            data["cgDelta1"] = cg.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            data["cgDelta2"] = cg.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            data["cgPoint1"] = cg.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            data["cgPoint2"] = cg.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
            data["cgFixed1"] = cg.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1)
            data["cgFixed2"] = cg.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2)
            data["cgSourcePID"] = cg.getIntegerValueField(.eventSourceUnixProcessID)
            data["cgUserData"] = cg.getIntegerValueField(.eventSourceUserData)
            data["cgContinuous"] = cg.getIntegerValueField(.scrollWheelEventIsContinuous)
        }
        write(data); return sequence
    }
    func handler(_ sequence: Int, layer: CALayer?) {
        guard enabled, let layer else { return }
        var data = state(layer)
        data["kind"] = "handler"; data["sequence"] = sequence; data["now"] = ProcessInfo.processInfo.systemUptime
        write(data)
    }
    func accepted(_ sequence: Int, step: Int, offset: Int, layer: CALayer?, center: NSPoint, before: NSPoint?) {
        guard enabled else { return }
        var data: [String: Any] = ["kind": "accepted", "sequence": sequence, "step": step, "offset": offset,
            "now": ProcessInfo.processInfo.systemUptime, "center": [center.x, center.y]]
        if let layer {
            active = (sequence, ProcessInfo.processInfo.systemUptime + 0.25, layer)
            data.merge(state(layer)) { _, new in new }
            if let before { data["before"] = [before.x, before.y] }
        }
        write(data)
    }
    func tick() {
        guard enabled, let active else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now <= active.until else { self.active = nil; return }
        var data = state(active.layer)
        data["kind"] = "sample"; data["sequence"] = active.sequence; data["now"] = now
        write(data)
    }
    private func state(_ layer: CALayer) -> [String: Any] {
        let ca = CACurrentMediaTime(), presentation = layer.presentation()
        let animation = layer.animation(forKey: "orbit")
        return ["layerID": String(describing: ObjectIdentifier(layer)), "model": [layer.position.x, layer.position.y],
            "presentation": presentation.map { [$0.position.x, $0.position.y] } ?? [],
            "keys": layer.animationKeys() ?? [], "begin": animation?.beginTime ?? -1,
            "duration": animation?.duration ?? 0, "caTime": ca,
            "localTime": layer.convertTime(ca, from: nil), "speed": layer.speed,
            "presentationScale": presentation.map { LayerGeometry.planarScale(of: $0) } ?? -1,
            "modelOpacity": layer.opacity, "presentationOpacity": presentation?.opacity ?? -1]
    }
    private func write(_ data: [String: Any]) {
        guard let json = try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys]),
              let line = String(data: json, encoding: .utf8) else { return }
        FileHandle.standardError.write(Data("[DEBUG-char-wheel-deep] \(line)\n".utf8))
    }
}
