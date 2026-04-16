import Foundation
import SwiftAgentCore

/// An in-process server transport that delivers requests directly to the
/// server actor without crossing a socket.
///
/// `InProcessServerTransport` exists for three scenarios:
///
/// 1. **Unit tests.** Drive the server end-to-end without spinning up a
///    network listener or dealing with ports and timeouts.
/// 2. **Same-app agents.** An app that hosts its own LLM (for example, a
///    local "chat with your notes" experience) can expose its own
///    `AgentTool`s to that in-process agent with zero ceremony. This is
///    a surprisingly common production case on-device.
/// 3. **Embedded MCP bridging.** Another subsystem in the same process
///    (a scripting engine, a Shortcut, an `AppIntent` perform-block)
///    can dispatch `JSONRPCRequest` messages against the transport and
///    receive typed responses without any wire format.
///
/// The transport is an `actor`, so concurrent dispatches from multiple
/// tasks are serialized correctly on the transport side as well as
/// inside the server.
public actor InProcessServerTransport: AgentServerTransport {
    private var handler: RequestHandler?

    /// Build an in-process transport. Nothing happens until
    /// ``start(handler:)`` is called by a server.
    public init() {}

    /// Store the server callback. Called by ``AgentServer/start(transport:)``.
    public func start(handler: @escaping RequestHandler) async throws {
        self.handler = handler
    }

    /// Release the server callback. Any in-flight ``deliver(_:)`` calls
    /// after this point will return `nil`.
    public func stop() async {
        self.handler = nil
    }

    /// Dispatch a request through the transport to the attached server.
    ///
    /// This is the method in-process clients use to talk to the server.
    /// Because the transport is an actor, repeated concurrent calls are
    /// safely serialized at the handoff point (the server itself is also
    /// an actor, so serialization is correct even across multiple
    /// in-process transports sharing the same server instance).
    ///
    /// - Parameter request: The request to dispatch.
    /// - Returns: The server's response, or `nil` if the request was a
    ///   notification or the transport has been stopped.
    public func deliver(_ request: JSONRPCRequest) async -> JSONRPCResponse? {
        guard let handler else { return nil }
        return await handler(request)
    }
}
