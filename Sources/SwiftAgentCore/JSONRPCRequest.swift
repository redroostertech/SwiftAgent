import Foundation

/// A JSON-RPC 2.0 request message.
///
/// A request is either a *call* (when `id` is non-nil — the sender expects a
/// matching ``JSONRPCResponse``) or a *notification* (when `id` is nil — the
/// sender expects no response). AppMCP uses notifications for
/// `notifications/initialized`, `notifications/cancelled`, and list-changed
/// events.
public struct JSONRPCRequest: Sendable, Codable, Hashable {
    /// JSON-RPC protocol version string. Always `"2.0"`.
    public let jsonrpc: String

    /// Request identifier, or `nil` for a notification.
    public let id: JSONRPCID?

    /// Method name being invoked (for example, `"tools/call"`).
    public let method: String

    /// Method parameters. Shape is method-specific; see ``MCPMethod``.
    public let params: JSONValue?

    /// Build a JSON-RPC request.
    ///
    /// - Parameters:
    ///   - id: The request identifier, or `nil` for a notification.
    ///   - method: The method name to invoke.
    ///   - params: The method parameters, if any.
    public init(id: JSONRPCID?, method: String, params: JSONValue? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }

    /// `true` when this request is a notification (no response expected).
    public var isNotification: Bool { id == nil }
}
