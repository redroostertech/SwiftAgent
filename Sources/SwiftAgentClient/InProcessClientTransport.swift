import Foundation
import SwiftAgentCore

/// A client transport that talks to an in-process server without going
/// through any networking.
///
/// Pair this with an `InProcessServerTransport` (from `AgentServer`) by
/// passing the same dispatch closure to both ends. The closure receives
/// a ``JSONRPCRequest`` and returns the matching response — typically
/// `{ await server.handle($0) }` for a directly-owned server instance.
///
/// This is the cleanest way to run an AppMCP server and client in the
/// same process — common in unit tests and in apps that host their own
/// LLM and want to expose the same tool surface to it that they would
/// expose to an external agent.
///
/// The transport is an `actor`, so concurrent dispatches from multiple
/// tasks are serialized correctly and no manual locking is required.
public actor InProcessClientTransport: AgentClientTransport {
    /// The dispatch closure that drives the in-process server.
    public typealias Dispatch = @Sendable (JSONRPCRequest) async -> JSONRPCResponse?

    private var dispatch: Dispatch?

    /// Build a client transport wired to the supplied dispatch closure.
    ///
    /// - Parameter dispatch: Called for every outgoing request. Should
    ///   forward the request to an in-process server and return the
    ///   response it produces. Return `nil` for notifications.
    public init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
    }

    /// Send a request through the in-process bridge and await the response.
    public func send(_ request: JSONRPCRequest) async throws -> JSONRPCResponse {
        guard let dispatch else { throw MCPError.transportClosed }
        guard let response = await dispatch(request) else {
            throw MCPError.transportClosed
        }
        return response
    }

    /// Send a notification. The dispatch closure is still invoked so the
    /// server can process it, but the returned nil response is discarded.
    public func notify(_ request: JSONRPCRequest) async throws {
        guard let dispatch else { throw MCPError.transportClosed }
        _ = await dispatch(request)
    }

    /// Close the transport. Subsequent sends throw ``MCPError/transportClosed``.
    public func close() async {
        dispatch = nil
    }
}
