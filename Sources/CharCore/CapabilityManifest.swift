import Foundation

public enum ClientInterface: String, Codable, Sendable { case cli, desktop, application }
public enum PluginCapability: String, Codable, CaseIterable, Sendable { case monitor, visit, origin, lifecycle }
public struct AdapterDescriptor: Codable, Equatable, Sendable {
    public enum Runtime: String, Codable, Sendable { case node, python3, executable }
    public var runtime: Runtime
    public var entrypoint: String
    public var capabilities: Set<PluginCapability>
    public var protocolVersion: Int
    public var configuration: [String: String]?
    public init(runtime: Runtime, entrypoint: String, capabilities: Set<PluginCapability>, protocolVersion: Int = 1, configuration: [String: String]? = nil) {
        self.runtime = runtime; self.entrypoint = entrypoint; self.capabilities = capabilities; self.protocolVersion = protocolVersion
        self.configuration = configuration
    }
}
