import Foundation

/// Parameters for the `initialize` request sent by the client to the server.
///
/// The initialize handshake is the very first request on any AppMCP
/// connection. The server inspects the offered protocol version and
/// capabilities and responds with its own ``MCPInitializeResult``. If the
/// versions are incompatible the server responds with
/// ``MCPError/unsupportedProtocolVersion(offered:supported:)``.
public struct MCPInitializeParams: Sendable, Hashable, Codable {
    /// The protocol version the client wishes to speak.
    public var protocolVersion: String

    /// Identity of the client implementation.
    public var clientInfo: MCPImplementation

    /// Capabilities the client is offering to the server.
    public var capabilities: MCPClientCapabilities

    /// Build initialize params.
    ///
    /// - Parameters:
    ///   - protocolVersion: The wire protocol version to negotiate.
    ///     Defaults to ``AgentProtocol/version``.
    ///   - clientInfo: Identity of this client.
    ///   - capabilities: Client-side capabilities being offered.
    public init(
        protocolVersion: String = AgentProtocol.version,
        clientInfo: MCPImplementation,
        capabilities: MCPClientCapabilities = MCPClientCapabilities()
    ) {
        self.protocolVersion = protocolVersion
        self.clientInfo = clientInfo
        self.capabilities = capabilities
    }
}
