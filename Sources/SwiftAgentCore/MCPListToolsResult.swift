import Foundation

/// Response payload for a `tools/list` call.
public struct MCPListToolsResult: Sendable, Hashable, Codable {
    /// The full set of tools the server currently exposes.
    public var tools: [MCPToolDescriptor]

    /// Build a tools-list result.
    public init(tools: [MCPToolDescriptor]) { self.tools = tools }
}
