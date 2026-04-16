import Foundation

/// Identification of a server or client implementation.
///
/// Sent as part of the `initialize` handshake so each side knows which
/// software it is talking to. The `bundleIdentifier` field is optional but
/// strongly encouraged for Apple-platform implementations since it provides
/// a stable, globally unique identifier independent of the display name.
public struct MCPImplementation: Sendable, Hashable, Codable {
    /// Human-readable name of the implementation (for example, `"Bear Notes"`).
    public var name: String

    /// Version string of the implementation. Semantic versions recommended.
    public var version: String

    /// Apple bundle identifier, when applicable. Stable across renames and
    /// localizations.
    public var bundleIdentifier: String?

    /// Build an implementation descriptor.
    ///
    /// - Parameters:
    ///   - name: Human-readable product name.
    ///   - version: Semantic version string.
    ///   - bundleIdentifier: Apple bundle id, if available.
    public init(name: String, version: String, bundleIdentifier: String? = nil) {
        self.name = name
        self.version = version
        self.bundleIdentifier = bundleIdentifier
    }
}
