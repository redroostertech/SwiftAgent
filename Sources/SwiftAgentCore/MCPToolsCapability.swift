import Foundation

/// Declares that a server offers the `tools/*` methods and, optionally, that
/// it will emit `notifications/tools/list_changed` when its tool catalog
/// mutates at runtime.
public struct MCPToolsCapability: Sendable, Hashable, Codable {
    /// When `true`, the server promises to send a
    /// `notifications/tools/list_changed` notification whenever its tool
    /// catalog changes, so clients can re-fetch instead of polling.
    public var listChanged: Bool?

    /// Build a tools capability descriptor.
    ///
    /// - Parameter listChanged: Whether the server supports live list-change
    ///   notifications.
    public init(listChanged: Bool? = nil) { self.listChanged = listChanged }
}
