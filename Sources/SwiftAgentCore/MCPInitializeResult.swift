import Foundation

/// Result returned by the server in response to an `initialize` request.
///
/// The result echoes the negotiated protocol version (which may differ from
/// the client's offer if the server elected to downgrade), identifies the
/// server implementation, advertises the capability bag, and may attach a
/// free-form `instructions` string that the client is expected to surface
/// to its LLM as pre-prompt context about how to use the server.
public struct MCPInitializeResult: Sendable, Hashable, Codable {
    /// The protocol version the server is committing to for this session.
    public var protocolVersion: String

    /// Identity of the server implementation.
    public var serverInfo: MCPImplementation

    /// Capabilities the server is offering to the client.
    public var capabilities: MCPServerCapabilities

    /// Optional free-form guidance for LLM clients. Typically included in
    /// the system prompt so the agent understands how to use this server's
    /// tools and resources correctly.
    public var instructions: String?

    /// Build an initialize result.
    ///
    /// - Parameters:
    ///   - protocolVersion: The negotiated wire protocol version. Defaults
    ///     to ``AgentProtocol/version``.
    ///   - serverInfo: Identity of this server.
    ///   - capabilities: Server-side capabilities being offered.
    ///   - instructions: Optional free-form guidance for LLM clients.
    public init(
        protocolVersion: String = AgentProtocol.version,
        serverInfo: MCPImplementation,
        capabilities: MCPServerCapabilities = MCPServerCapabilities(),
        instructions: String? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.serverInfo = serverInfo
        self.capabilities = capabilities
        self.instructions = instructions
    }
}
