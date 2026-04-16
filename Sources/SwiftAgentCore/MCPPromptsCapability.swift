import Foundation

/// Declares that a server offers the `prompts/*` methods and, optionally,
/// supports live prompt-list change notifications.
public struct MCPPromptsCapability: Sendable, Hashable, Codable {
    /// When `true`, the server promises to emit
    /// `notifications/prompts/list_changed` when its prompt catalog mutates.
    public var listChanged: Bool?

    /// Build a prompts capability descriptor.
    public init(listChanged: Bool? = nil) { self.listChanged = listChanged }
}
