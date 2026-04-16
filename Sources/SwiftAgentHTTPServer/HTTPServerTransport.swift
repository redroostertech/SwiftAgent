import Foundation
import SwiftAgentCore
import SwiftAgentServer

/// MCP Streamable HTTP server transport.
///
/// Implements the MCP 2025-06-18 Streamable HTTP transport specification:
/// clients POST JSON-RPC requests to an endpoint, the server responds
/// with JSON or an SSE stream, and server-initiated notifications flow
/// over a long-lived SSE connection.
///
/// Phase 3 implementation — the full version uses `NWListener` with
/// HTTP message framing (`NWProtocolHTTP`) and SSE for notifications.
/// Currently a placeholder to unblock Package.swift resolution.
public final class HTTPServerTransport: AgentServerTransport, @unchecked Sendable {
    /// Build an HTTP server transport on the specified port.
    public init(port: UInt16 = 0) {
        // Phase 3: full NWListener + HTTP implementation
    }

    public func start(handler: @escaping RequestHandler) async throws {
        // Phase 3
    }

    public func stop() async {
        // Phase 3
    }
}
