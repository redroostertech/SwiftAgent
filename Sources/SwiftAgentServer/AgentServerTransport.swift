import Foundation
import SwiftAgentCore

/// The abstraction every AppMCP server transport implements.
///
/// A transport is responsible for moving framed JSON-RPC messages
/// between the server actor and the outside world. It knows nothing
/// about MCP semantics (initialize handshakes, tool calls, etc.) —
/// those live in ``AgentServer``. This separation lets the same
/// server actor run on top of an in-process pipe for unit tests, a
/// Bonjour-advertised TCP listener on macOS, or an App-Intents bridge
/// on iOS, with zero changes to the business logic.
///
/// Transports are expected to:
///
/// - Deliver inbound ``JSONRPCRequest`` values to the server via
///   ``start(handler:)``, and await the returned response (if any)
///   before accepting the next request on the same connection.
/// - Support clean shutdown via ``stop()``, unblocking any pending
///   reads and releasing operating-system resources.
///
/// The handler supplied to ``start(handler:)`` is actor-isolated in
/// practice — transports should call it with `await` and forward the
/// resulting response back on the same logical connection.
public protocol AgentServerTransport: Sendable {
    /// Alias for the server-side request handler signature.
    typealias RequestHandler = @Sendable (JSONRPCRequest) async -> JSONRPCResponse?

    /// Begin accepting requests. Returns once the transport is ready
    /// to receive traffic; further work happens on the transport's
    /// internal task(s).
    ///
    /// - Parameter handler: The server callback that consumes each
    ///   incoming request and returns a response (or `nil` for
    ///   notifications, which expect no response).
    /// - Throws: Any error raised while setting up the transport
    ///   (port binding, file descriptor allocation, etc.).
    func start(handler: @escaping RequestHandler) async throws

    /// Stop the transport and release its resources. Safe to call
    /// multiple times; idempotent.
    func stop() async
}
