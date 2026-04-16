import Foundation
import SwiftAgentCore

/// The abstraction every AppMCP client transport implements.
///
/// A client transport is the dual of ``AgentServerTransport`` (in the
/// `AgentServer` module): it moves framed JSON-RPC messages between
/// an ``AgentClient`` and a remote server, and nothing more. MCP
/// semantics (initialize handshakes, tool calls, matching requests to
/// responses) live in the client itself, so any concrete transport can
/// be paired with the generic client shell.
///
/// A compliant transport must:
///
/// - Guarantee that ``send(_:)`` delivers the request to the peer
///   exactly once and returns the peer's response, or throws on
///   transport failure.
/// - Support clean shutdown via ``close()``, which unblocks any
///   pending ``send(_:)`` calls with a transport-closed error.
/// - Be safe to share across concurrent tasks. Actor-based transports
///   are preferred; class-based transports must document their
///   thread-safety guarantees.
///
/// Notifications (requests with `id == nil`) are sent with ``notify(_:)``
/// and intentionally do not block — the transport should return as
/// soon as the message is enqueued on the wire.
public protocol AgentClientTransport: Sendable {
    /// Send a request and wait for the matching response.
    ///
    /// - Parameter request: The request to send. Must have a non-nil id.
    /// - Returns: The peer's response.
    /// - Throws: ``MCPError/transportClosed`` if the transport has been
    ///   closed, or any transport-specific error encountered during I/O.
    func send(_ request: JSONRPCRequest) async throws -> JSONRPCResponse

    /// Send a notification without waiting for a response.
    ///
    /// - Parameter request: The notification to send. The id must be `nil`.
    /// - Throws: ``MCPError/transportClosed`` if the transport has been closed.
    func notify(_ request: JSONRPCRequest) async throws

    /// Close the transport and release its resources. Any in-flight
    /// ``send(_:)`` calls must throw before this method returns.
    /// Idempotent.
    func close() async
}
