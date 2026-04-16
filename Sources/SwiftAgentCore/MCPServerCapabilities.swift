import Foundation

/// Capability bag advertised by a server during `initialize`.
///
/// Every field is optional so that new capabilities can be added in future
/// protocol revisions without breaking older clients. A missing capability
/// means "not offered"; a client that asks for a missing capability should
/// receive ``MCPError/custom(code:message:data:)`` or a method-not-found
/// error.
public struct MCPServerCapabilities: Sendable, Hashable, Codable {
    /// Tools capability, if the server exposes any `tools/*` methods.
    public var tools: MCPToolsCapability?

    /// Resources capability, if the server exposes any `resources/*` methods.
    public var resources: MCPResourcesCapability?

    /// Prompts capability, if the server exposes any `prompts/*` methods.
    public var prompts: MCPPromptsCapability?

    /// Logging capability, if the server streams log notifications to clients.
    public var logging: MCPLoggingCapability?

    /// Build a server capability bag.
    ///
    /// - Parameters:
    ///   - tools: Tools capability, or `nil` if not offered.
    ///   - resources: Resources capability, or `nil` if not offered.
    ///   - prompts: Prompts capability, or `nil` if not offered.
    ///   - logging: Logging capability, or `nil` if not offered.
    public init(
        tools: MCPToolsCapability? = nil,
        resources: MCPResourcesCapability? = nil,
        prompts: MCPPromptsCapability? = nil,
        logging: MCPLoggingCapability? = nil
    ) {
        self.tools = tools
        self.resources = resources
        self.prompts = prompts
        self.logging = logging
    }
}
