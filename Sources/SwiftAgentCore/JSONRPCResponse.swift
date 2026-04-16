import Foundation

/// A JSON-RPC 2.0 response message.
///
/// Exactly one of `result` or `error` is populated, never both. Construct
/// via the dedicated initializers rather than setting fields directly.
public struct JSONRPCResponse: Sendable, Codable, Hashable {
    /// JSON-RPC protocol version string. Always `"2.0"`.
    public let jsonrpc: String

    /// The id of the request this response is for. May be `nil` only when
    /// the server was unable to parse the id from the original request.
    public let id: JSONRPCID?

    /// The successful result payload. `nil` if this response is an error.
    public let result: JSONValue?

    /// The error payload. `nil` if this response is a success.
    public let error: JSONRPCError?

    /// Build a success response.
    ///
    /// - Parameters:
    ///   - id: The id of the originating request.
    ///   - result: The method's return value.
    public init(id: JSONRPCID?, result: JSONValue) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = nil
    }

    /// Build an error response.
    ///
    /// - Parameters:
    ///   - id: The id of the originating request. May be `nil` if the id
    ///     could not be recovered.
    ///   - error: The error payload to return to the caller.
    public init(id: JSONRPCID?, error: JSONRPCError) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = nil
        self.error = error
    }
}
