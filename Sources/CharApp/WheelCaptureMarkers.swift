import Carbon

/// [DEBUG-char-wheel-deep] Two explicit experiment markers; no keyboard monitoring.
@MainActor final class WheelCaptureMarkers {
    private var keys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private let action: @MainActor (String) -> Void
    private(set) var status: OSStatus = noErr
    init(action: @escaping @MainActor (String) -> Void) {
        self.action = action
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        status = InstallEventHandler(GetEventDispatcherTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                          MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == 0x43574d4b, (1...2).contains(id.id) else { return OSStatus(eventNotHandledErr) }
            let marker = Unmanaged<WheelCaptureMarkers>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { marker.action(id.id == 1 ? "begin" : "heldEnd") }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { return }
        for (key, id) in [(kVK_ANSI_9, UInt32(1)), (kVK_ANSI_0, UInt32(2))] {
            var ref: EventHotKeyRef?
            status = RegisterEventHotKey(UInt32(key), UInt32(controlKey | shiftKey), EventHotKeyID(signature: 0x43574d4b, id: id),
                                         GetEventDispatcherTarget(), OptionBits(kEventHotKeyExclusive), &ref)
            guard status == noErr, let ref else { stop(); return }
            keys.append(ref)
        }
    }
    func stop() {
        for key in keys { UnregisterEventHotKey(key) }; keys.removeAll()
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }
    deinit { for key in keys { UnregisterEventHotKey(key) }; if let handler { RemoveEventHandler(handler) } }
}
