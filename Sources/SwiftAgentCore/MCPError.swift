import Foundation

/// Errors raised by AppMCP at the protocol and tool-invocation layers.
///
/// `MCPError` maps cleanly onto JSON-RPC errors via ``jsonRPCError``, so
/// handlers can `throw` a typed Swift error and the transport renders the
/// correct wire format automatically.
///
/// AppMCP reserves the following numeric ranges inside the JSON-RPC
/// "server error" space (−32000 … −32099) and its own tool range:
///
/// | Range                | Meaning                                   |
/// |----------------------|-------------------------------------------|
/// | −32000 … −32099      | Protocol-level AppMCP errors              |
/// | −32100 … −32199      | Tool-execution errors                     |
///
/// Use ``custom(code:message:data:)`` to surface an error from your own
/// reserved space while staying Swift-typed.
public enum MCPError: Error, Sendable, Hashable {
    /// A request was received before the `initialize` handshake completed.
    case notInitialized
    /// A second `initialize` request was received after the first succeeded.
    case alreadyInitialized
    /// The client offered a protocol version the server does not implement.
    case unsupportedProtocolVersion(offered: String, supported: [String])
    /// A `tools/call` referenced a tool name that is not registered.
    case toolNotFound(name: String)
    /// A tool handler threw or otherwise failed during execution.
    case toolExecutionFailed(name: String, message: String)
    /// A `tools/call` had arguments that did not validate against the tool's
    /// declared input schema.
    case invalidToolArguments(name: String, reason: String)
    /// The underlying transport closed mid-request.
    case transportClosed
    /// The operation was cancelled via `notifications/cancelled` or a Swift
    /// `Task.cancel()`.
    case cancelled
    /// An application-defined error. Use this to surface errors from your
    /// own reserved code range without extending ``MCPError``.
    case custom(code: Int, message: String, data: JSONValue? = nil)

    /// The JSON-RPC numeric code this error maps to on the wire.
    public var code: Int {
        switch self {
        case .notInitialized: -32002
        case .alreadyInitialized: -32003
        case .unsupportedProtocolVersion: -32004
        case .toolNotFound: -32100
        case .toolExecutionFailed: -32101
        case .invalidToolArguments: -32102
        case .transportClosed: -32010
        case .cancelled: -32011
        case .custom(let code, _, _): code
        }
    }

    /// Short, human-readable description suitable for surfacing to users or
    /// log sinks. Messages are intentionally plain English — detailed
    /// diagnostics belong in ``data``.
    public var message: String {
        switch self {
        case .notInitialized:
            "Server has not completed the initialize handshake."
        case .alreadyInitialized:
            "Server has already been initialized."
        case .unsupportedProtocolVersion(let offered, let supported):
            "Unsupported protocol version '\(offered)'. Supported: \(supported.joined(separator: ", "))."
        case .toolNotFound(let name):
            "Tool not found: \(name)"
        case .toolExecutionFailed(let name, let message):
            "Tool '\(name)' failed: \(message)"
        case .invalidToolArguments(let name, let reason):
            "Invalid arguments for tool '\(name)': \(reason)"
        case .transportClosed:
            "Transport is closed."
        case .cancelled:
            "Operation was cancelled."
        case .custom(_, let message, _):
            message
        }
    }

    /// Optional structured metadata for clients that want to react to
    /// specific error conditions programmatically — for example, pulling
    /// the `tool` key to show the affected tool in a UI.
    public var data: JSONValue? {
        switch self {
        case .unsupportedProtocolVersion(let offered, let supported):
            .object([
                "offered": .string(offered),
                "supported": .array(supported.map { .string($0) })
            ])
        case .toolNotFound(let name), .toolExecutionFailed(let name, _), .invalidToolArguments(let name, _):
            .object(["tool": .string(name)])
        case .custom(_, _, let data):
            data
        default:
            nil
        }
    }

    /// Convert this typed error into its JSON-RPC wire representation.
    ///
    /// Transports call this automatically when a handler throws
    /// ``MCPError``; user code rarely needs to invoke it directly.
    public var jsonRPCError: JSONRPCError {
        JSONRPCError(code: code, message: message, data: data)
    }
}
