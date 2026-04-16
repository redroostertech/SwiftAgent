import Foundation

/// Optional behavioral hints attached to a tool descriptor.
///
/// Annotations let an agent reason about the consequences of calling a
/// tool *before* calling it. None of them are enforced by the protocol —
/// they are advisory, and a safety-aware agent host is expected to consult
/// them when deciding whether to auto-approve, confirm with the user, or
/// present the call in a sandbox.
///
/// Borrowed from the MCP 2025-03-26 revision.
public struct MCPToolAnnotations: Sendable, Hashable, Codable {
    /// `true` when the tool never mutates any state the user cares about.
    /// Agents may auto-approve read-only calls more aggressively.
    public var readOnly: Bool?

    /// `true` when a failed or mistaken invocation cannot be safely undone
    /// (e.g. deleting a file, sending a message). Agents should surface
    /// explicit confirmation for destructive calls.
    public var destructive: Bool?

    /// `true` when calling the tool with the same arguments twice produces
    /// the same effect as calling it once.
    public var idempotent: Bool?

    /// `true` when the tool reaches out to an "open world" (network, web,
    /// other users, external APIs) as opposed to staying entirely within
    /// the host app's local state.
    public var openWorld: Bool?

    /// `true` when the tool requires explicit user confirmation before
    /// running, regardless of agent auto-approval policy.
    public var requiresUserConfirmation: Bool?

    /// Build a tool annotation descriptor.
    public init(
        readOnly: Bool? = nil,
        destructive: Bool? = nil,
        idempotent: Bool? = nil,
        openWorld: Bool? = nil,
        requiresUserConfirmation: Bool? = nil
    ) {
        self.readOnly = readOnly
        self.destructive = destructive
        self.idempotent = idempotent
        self.openWorld = openWorld
        self.requiresUserConfirmation = requiresUserConfirmation
    }
}
