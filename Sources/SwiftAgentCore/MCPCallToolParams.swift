import Foundation

/// Parameters for a `tools/call` request.
public struct MCPCallToolParams: Sendable, Hashable, Codable {
    /// Name of the tool to invoke. Must match a ``MCPToolDescriptor/name``
    /// returned from `tools/list`.
    public var name: String

    /// Arguments to pass to the tool, validated against the tool's
    /// declared ``MCPToolDescriptor/inputSchema``. `nil` is equivalent to
    /// an empty object.
    public var arguments: JSONValue?

    /// Build call-tool params.
    public init(name: String, arguments: JSONValue? = nil) {
        self.name = name
        self.arguments = arguments
    }
}
