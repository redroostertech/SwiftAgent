import Foundation

/// A JSON-RPC 2.0 error object.
///
/// Conforms to `Error` so implementations can `throw` it directly from
/// request handlers and the transport will package it into a response.
///
/// AppMCP-specific codes live in ``MCPError``; this type is the raw wire
/// representation.
public struct JSONRPCError: Sendable, Codable, Hashable, Error {
    /// The numeric error code. See the JSON-RPC 2.0 spec and ``MCPError``.
    public let code: Int

    /// A short, human-readable description of the error.
    public let message: String

    /// Optional structured metadata about the error, for programmatic use
    /// by clients. AppMCP uses this to attach the offending tool name,
    /// protocol version lists, and validation error paths.
    public let data: JSONValue?

    /// Build a JSON-RPC error value.
    ///
    /// - Parameters:
    ///   - code: The numeric error code.
    ///   - message: Human-readable description.
    ///   - data: Optional structured metadata.
    public init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    // MARK: Standard JSON-RPC 2.0 error codes

    /// `-32700 Parse error` — invalid JSON was received by the server.
    public static func parseError(_ message: String = "Parse error") -> JSONRPCError {
        JSONRPCError(code: -32700, message: message)
    }

    /// `-32600 Invalid Request` — the JSON sent is not a valid request object.
    public static func invalidRequest(_ message: String = "Invalid Request") -> JSONRPCError {
        JSONRPCError(code: -32600, message: message)
    }

    /// `-32601 Method not found` — the method does not exist or is unavailable.
    public static func methodNotFound(_ method: String) -> JSONRPCError {
        JSONRPCError(code: -32601, message: "Method not found: \(method)")
    }

    /// `-32602 Invalid params` — method parameters are structurally invalid.
    public static func invalidParams(_ message: String = "Invalid params") -> JSONRPCError {
        JSONRPCError(code: -32602, message: message)
    }

    /// `-32603 Internal error` — an unexpected condition inside the server.
    public static func internalError(_ message: String = "Internal error") -> JSONRPCError {
        JSONRPCError(code: -32603, message: message)
    }
}
