import AppKit
import QuartzCore

/// [DEBUG-char-wheel-deep] Temporary, opt-in boundary trace; contains geometry only.
@MainActor final class WheelDiagnostics {
    private let enabled = ProcessInfo.processInfo.environment["CHAR_WHEEL_DIAGNOSTICS"] == "1"
    private var sequence = 0
    private var active: (sequence: Int, until: TimeInterval, layer: CALayer)?
    private var monitors: [Any] = []
    private var lastRoute: String?
    private weak var rawSurface: CompanionSurface?
    private var rawTaps: [(CFMachPort, CFRunLoopSource)] = []
    private var markers: WheelCaptureMarkers?
    // [DEBUG-char-wheel-deep] Passive input boundaries; never consume or repost events.
    func monitor(_ surface: CompanionSurface) {
        stopMonitoring()
        guard enabled else { return }
        let rawAllowed = CGPreflightListenEventAccess()
        write(["kind": "rawAccess", "now": ProcessInfo.processInfo.systemUptime, "allowed": rawAllowed])
        if ProcessInfo.processInfo.environment["CHAR_RAW_WHEEL_DIAGNOSTICS"] == "1", rawAllowed {
            rawSurface = surface
            installRawTap(location: .cghidEventTap, placement: .headInsertEventTap, callback: { _, type, event, context in
                if type == .scrollWheel, let context {
                    MainActor.assumeIsolated { Unmanaged<WheelDiagnostics>.fromOpaque(context).takeUnretainedValue().rawInput(event, kind: "rawHID") }
                }
                return Unmanaged.passUnretained(event)
            })
            installRawTap(location: .cgSessionEventTap, placement: .tailAppendEventTap, callback: { _, type, event, context in
                if type == .scrollWheel, let context {
                    MainActor.assumeIsolated { Unmanaged<WheelDiagnostics>.fromOpaque(context).takeUnretainedValue().rawInput(event, kind: "rawSession") }
                }
                return Unmanaged.passUnretained(event)
            })
            write(["kind": "rawTapsInstalled", "count": rawTaps.count, "now": ProcessInfo.processInfo.systemUptime])
            markers = WheelCaptureMarkers { [weak self] name in
                self?.write(["kind": "marker", "name": name, "now": ProcessInfo.processInfo.systemUptime])
            }
            write(["kind": "markersInstalled", "status": markers?.status ?? -1])
        }
        if let token = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self, weak surface] event in
            MainActor.assumeIsolated {
                if let surface { self?.ingress(event, surface: surface, kind: "ingressLocal") }
            }
            return event
        }) { monitors.append(token) }
        if let token = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: { [weak self, weak surface] event in
            MainActor.assumeIsolated {
                if let surface, surface.window?.frame.contains(NSEvent.mouseLocation) == true {
                    self?.ingress(event, surface: surface, kind: "ingressGlobal")
                }
            }
        }) { monitors.append(token) }
        write(["kind": "monitorInstalled", "now": ProcessInfo.processInfo.systemUptime, "count": monitors.count])
    }
    func stopMonitoring() {
        for token in monitors { NSEvent.removeMonitor(token) }; monitors.removeAll()
        for (tap, source) in rawTaps {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFMachPortInvalidate(tap)
        }
        rawTaps.removeAll(); rawSurface = nil
        markers?.stop(); markers = nil
    }
    private func installRawTap(location: CGEventTapLocation, placement: CGEventTapPlacement, callback: CGEventTapCallBack) {
        guard let tap = CGEvent.tapCreate(tap: location, place: placement, options: .listenOnly,
                                         eventsOfInterest: 1 << CGEventType.scrollWheel.rawValue,
                                         callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else { return }
        rawTaps.append((tap, source)); CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }
    private func rawInput(_ event: CGEvent, kind: String) {
        guard let surface = rawSurface, let window = surface.window, let screenTop = NSScreen.screens.first?.frame.maxY else { return }
        let point = NSPoint(x: event.location.x, y: screenTop-event.location.y)
        guard window.frame.contains(point) else { return }
        write(["kind": kind, "now": ProcessInfo.processInfo.systemUptime,
               "nativeTimestamp": String(event.timestamp),
               "screenPoint": [point.x,point.y],
               "line": event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
               "pixels": event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1),
               "continuous": event.getIntegerValueField(.scrollWheelEventIsContinuous),
               "sourcePID": event.getIntegerValueField(.eventSourceUnixProcessID)])
    }
    func route(_ surface: CompanionSurface, point: NSPoint, accepts: Bool) {
        guard enabled else { return }
        let target = (surface.hitTest(point) as? GraphicButton)?.renderedWorkEnd?.rawValue ?? "surface/none"
        let key = "\(accepts):\(target)"
        guard key != lastRoute else { return }; lastRoute = key
        write(["kind": "route", "now": ProcessInfo.processInfo.systemUptime, "accepts": accepts,
               "target": target, "point": [point.x,point.y], "appActive": NSApp.isActive])
    }
    private func ingress(_ event: NSEvent, surface: CompanionSurface, kind: String) {
        guard let window = surface.window else { return }
        let point = surface.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        write(["kind": kind, "now": ProcessInfo.processInfo.systemUptime, "eventTime": event.timestamp,
               "dy": event.scrollingDeltaY, "dx": event.scrollingDeltaX, "point": [point.x,point.y],
               "accepts": !window.ignoresMouseEvents, "eventWindow": event.windowNumber,
               "panelWindow": window.windowNumber, "appActive": NSApp.isActive, "panelKey": window.isKeyWindow,
               "sourcePID": event.cgEvent?.getIntegerValueField(.eventSourceUnixProcessID) ?? -1])
    }
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
