import Carbon
import Foundation

public enum HomeShortcutStatus: Equatable, Sendable {
    case inactive, registered, failed(Int32)
}

@MainActor public protocol HomeHotKeyService: AnyObject {
    func register(_ action: @escaping @MainActor () -> Void) -> Int32
    func unregister() -> Int32
}

/// Holds Ctrl+B only while a return anchor exists. A failed registration is explicitly retryable.
@MainActor public final class HomeShortcutController {
    private let service: any HomeHotKeyService
    private let action: @MainActor () -> Void
    private var hasHold = false
    private var registered = false
    public private(set) var status: HomeShortcutStatus = .inactive

    public init(service: any HomeHotKeyService, action: @escaping @MainActor () -> Void) {
        self.service = service; self.action = action
    }
    public convenience init(action: @escaping @MainActor () -> Void) {
        self.init(service: CarbonHomeHotKeyService(), action: action)
    }
    public func updateHold(_ active: Bool) {
        let began = active && !hasHold
        hasHold = active
        if active {
            if registered { status = .registered }
            else if began { register() }
        } else if registered {
            let result = service.unregister()
            if result == noErr { registered = false; status = .inactive }
            else { status = .failed(result) }
        } else { status = .inactive }
    }
    public func retry() {
        guard hasHold, !registered else { return }
        register()
    }
    private func register() {
        let result = service.register { [weak self] in
            guard let self, self.hasHold, self.registered else { return }
            self.action()
        }
        registered = result == noErr
        status = registered ? .registered : .failed(result)
    }
}

/// Apple CarbonEvents.h specifies exclusive registration and reports eventHotKeyExistsErr for conflicts.
/// These main-thread APIs require no event tap, global key monitor or keyboard permission request.
@MainActor public final class CarbonHomeHotKeyService: HomeHotKeyService {
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var action: (@MainActor () -> Void)?
    private static let signature: OSType = 0x43686172 // Char
    public init() {}
    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    public func register(_ action: @escaping @MainActor () -> Void) -> Int32 {
        if hotKey != nil { self.action = action; return noErr }
        self.action = action
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerResult = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                          nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard result == noErr, identifier.signature == 0x43686172, identifier.id == 1 else { return OSStatus(eventNotHandledErr) }
            let service = Unmanaged<CarbonHomeHotKeyService>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { service.action?() }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        guard handlerResult == noErr else { self.action = nil; return handlerResult }
        let result = RegisterEventHotKey(UInt32(kVK_ANSI_B), UInt32(controlKey),
            EventHotKeyID(signature: Self.signature, id: 1), GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &hotKey)
        if result != noErr { removeHandler(); self.action = nil }
        return result
    }
    public func unregister() -> Int32 {
        guard let hotKey else { removeHandler(); action = nil; return noErr }
        let result = UnregisterEventHotKey(hotKey)
        if result == noErr { self.hotKey = nil; removeHandler(); action = nil }
        return result
    }
    private func removeHandler() {
        if let eventHandler { RemoveEventHandler(eventHandler); self.eventHandler = nil }
    }
}
