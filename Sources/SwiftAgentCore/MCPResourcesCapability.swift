import Foundation

/// Declares that a server offers the `resources/*` methods and, optionally,
/// supports subscriptions and list-change notifications.
public struct MCPResourcesCapability: Sendable, Hashable, Codable {
    /// When `true`, clients may call `resources/subscribe` to receive
    /// change notifications for individual resources.
    public var subscribe: Bool?

    /// When `true`, the server promises to emit
    /// `notifications/resources/list_changed` when the catalog mutates.
    public var listChanged: Bool?

    /// Build a resources capability descriptor.
    ///
    /// - Parameters:
    ///   - subscribe: Whether per-resource subscriptions are supported.
    ///   - listChanged: Whether catalog list-change notifications are emitted.
    public init(subscribe: Bool? = nil, listChanged: Bool? = nil) {
        self.subscribe = subscribe
        self.listChanged = listChanged
    }
}
