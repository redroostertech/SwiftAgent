import Foundation

/// Declares that a server will emit `notifications/message` log entries
/// to the client for observability purposes. Presence alone signals
/// support — no fields are required today, though future revisions may
/// add opt-in capability flags.
public struct MCPLoggingCapability: Sendable, Hashable, Codable {
    /// Build a logging capability descriptor.
    public init() {}
}
