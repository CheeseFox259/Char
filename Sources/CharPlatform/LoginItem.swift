import Foundation
import CharCore
import ServiceManagement
import CoreServices

public enum LoginItemState: Equatable, Sendable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable(LoginItemUnavailability)
}

public enum LoginItemUnavailability: Equatable, Sendable {
    case notPackaged, unknownStatus
    public func message(language: AppLanguage) -> String {
        switch self {
        case .notPackaged: return language == .chinese ? "登录时启动需要打包的 Char.app。" : "Launch-at-login requires the packaged Char.app."
        case .unknownStatus: return language == .chinese ? "ServiceManagement 状态未知。" : "Unknown ServiceManagement status."
        }
    }
}

public enum LoginItemError: LocalizedError, Equatable {
    case notPackaged
    case failed(String)
    case unavailable(LoginItemUnavailability)

    public var errorDescription: String? { message(language: .systemDefault) }
    public func message(language: AppLanguage) -> String {
        switch self {
        case .notPackaged: return LoginItemUnavailability.notPackaged.message(language: language)
        case let .unavailable(reason): return reason.message(language: language)
        case let .failed(diagnostic):
            return (language == .chinese ? "无法更新登录时启动：" : "Could not update launch-at-login: ") + diagnostic
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
        if case let .unavailable(reason) = status { throw LoginItemError.unavailable(reason) }
        do {
            if enabled { try service.register() } else { try service.unregister() }
        } catch let error as LoginItemError {
            throw error
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
            return .unavailable(.notPackaged)
        }
        return Self.state(for: SMAppService.mainApp.status)
    }

    public static func state(for status: SMAppService.Status) -> LoginItemState {
        switch status {
        case .enabled: return .enabled
        case .notRegistered: return .disabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .disabled
        @unknown default: return .unavailable(.unknownStatus)
        }
    }

    public func register() throws {
        guard Bundle.main.bundleURL.pathExtension == "app" else { throw LoginItemError.notPackaged }
        // Refresh registration for this installed bundle before ServiceManagement resolves mainApp.
        let result = LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
        guard result == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(result)) }
        try SMAppService.mainApp.register()
    }

    public func unregister() throws {
        guard Bundle.main.bundleURL.pathExtension == "app" else { throw LoginItemError.notPackaged }
        try SMAppService.mainApp.unregister()
    }
}
