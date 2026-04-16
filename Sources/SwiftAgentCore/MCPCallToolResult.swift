import Foundation

/// Result returned from a successful (or gracefully failed) `tools/call`.
///
/// A tool call can "fail" in two different ways:
///
/// 1. **Protocol failure** — the tool was never executed because the
///    arguments did not match the schema, the tool was not found, or the
///    transport died. This is surfaced as a JSON-RPC ``JSONRPCError``.
/// 2. **Semantic failure** — the tool ran but produced an error result
///    (for example, "note not found", "permission denied"). This is
///    surfaced as an ``MCPCallToolResult`` with ``isError`` set to `true`
///    and an explanatory message in ``content``.
///
/// The two categories exist so agents can tell apart "I typed the wrong
/// number of arguments" (retry with different shape) from "the tool
/// returned that this couldn't be done" (adjust strategy).
public struct MCPCallToolResult: Sendable, Hashable, Codable {
    /// The ordered list of content blocks returned by the tool. Clients
    /// should render every block, typically concatenating text pieces.
    public var content: [MCPContent]

    /// `true` when this represents a semantic failure — the tool ran but
    /// the operation could not be completed. The ``content`` should
    /// contain the human-readable explanation.
    public var isError: Bool

    /// Optional structured payload that parallels the rendered ``content``.
    /// Agents that prefer machine-readable output should read this first
    /// and fall back to the text blocks when absent.
    public var structured: JSONValue?

    /// Build a tool-call result.
    public init(content: [MCPContent], isError: Bool = false, structured: JSONValue? = nil) {
        self.content = content
        self.isError = isError
        self.structured = structured
    }

    /// Shorthand for a single-text-block success result.
    public static func text(_ string: String) -> MCPCallToolResult {
        MCPCallToolResult(content: [.text(string)])
    }

    /// Shorthand for a structured-JSON success result. Also populates the
    /// ``structured`` field so the caller can read either shape.
    public static func json(_ value: JSONValue) -> MCPCallToolResult {
        MCPCallToolResult(content: [.json(value)], structured: value)
    }

    /// Shorthand for a semantic-failure result.
    public static func failure(_ message: String) -> MCPCallToolResult {
        MCPCallToolResult(content: [.text(message)], isError: true)
    }
}
