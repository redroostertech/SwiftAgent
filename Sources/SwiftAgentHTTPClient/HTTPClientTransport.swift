import Foundation
import SwiftAgentCore
import SwiftAgentClient

/// MCP Streamable HTTP client transport.
///
/// Implements the client side of the MCP 2025-06-18 Streamable HTTP
/// transport: sends JSON-RPC requests as HTTP POSTs, receives responses
/// as JSON bodies or SSE streams, and maintains session identity via
/// the `Mcp-Session-Id` header.
///
/// Uses `URLSession` exclusively — no Network.framework dependency on
/// the client side — so it works on every Apple platform including
/// watchOS where NWConnection is unavailable.
///
/// Phase 3 implementation — currently a placeholder.
public final class HTTPClientTransport: AgentClientTransport, @unchecked Sendable {
    private let url: URL

    /// Build an HTTP client transport pointed at a remote MCP server.
    ///
    /// - Parameter url: The server's MCP endpoint URL (e.g.
    ///   `http://localhost:3000/mcp`).
    public init(url: URL) {
        self.url = url
    }

    public func send(_ request: JSONRPCRequest) async throws -> JSONRPCResponse {
        // Phase 3: full URLSession + SSE implementation
        throw MCPError.transportClosed
    }

    public func notify(_ request: JSONRPCRequest) async throws {
        // Phase 3
    }

    public func close() async {
        // Phase 3
    }
}
