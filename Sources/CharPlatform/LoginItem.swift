import Foundation
import ServiceManagement

public enum LoginItemState: Equatable, Sendable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable(String)
}

public enum LoginItemError: LocalizedError {
    case notPackaged
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .notPackaged: return "Launch-at-login can be changed only from the packaged Char.app."
        case let .failed(message): return "Could not update launch-at-login: \(message)"
        }
    }
}

@MainActor public protocol LoginService {
    var state: LoginItemState { get }
    func register() throws
    func unregister() throws
}

@MainActor public final class LoginItemController {
    private let service: any LoginService

    public init(service: any LoginService) { self.service = service }
    public convenience init() { self.init(service: MainAppLoginService()) }

    /// The actual ServiceManagement state, never a stored preference's requested value.
    public var status: LoginItemState { service.state }

    @discardableResult public func setEnabled(_ enabled: Bool) throws -> LoginItemState {
        if enabled && status == .enabled { return status }
        if enabled && status == .requiresApproval { return status }
        if !enabled && status == .disabled { return status }
        if case let .unavailable(message) = status { throw LoginItemError.failed(message) }
        do {
            if enabled { try service.register() } else { try service.unregister() }
        } catch {
            throw LoginItemError.failed(error.localizedDescription)
        }
        return status
    }
}

@MainActor public final class MainAppLoginService: LoginService {
    public init() {}

    public var state: LoginItemState {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return .unavailable("Launch-at-login requires the packaged Char.app.")
        }
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .notRegistered: return .disabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .unavailable("Char.app is not registered with ServiceManagement.")
        @unknown default: return .unavailable("Unknown ServiceManagement status.")
        }
    }

    public func register() throws {
        guard Bundle.main.bundleURL.pathExtension == "app" else { throw LoginItemError.notPackaged }
        try SMAppService.mainApp.register()
    }

    public func unregister() throws {
        guard Bundle.main.bundleURL.pathExtension == "app" else { throw LoginItemError.notPackaged }
        try SMAppService.mainApp.unregister()
    }
}
