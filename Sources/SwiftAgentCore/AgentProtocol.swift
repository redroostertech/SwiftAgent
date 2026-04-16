import Foundation

/// Version of the AppMCP wire protocol implemented by this package.
///
/// AppMCP follows the Model Context Protocol naming convention of using a
/// date-based version string. Bump this when you make a breaking change to
/// any on-the-wire message structure. Minor non-breaking additions (new
/// optional fields) do **not** require a version bump — clients are
/// expected to ignore unknown fields.
public enum AgentProtocol {
    /// The wire protocol version this build speaks.
    public static let version = "2026-04-15"

    /// All protocol versions this build can fully implement.
    public static let supportedVersions: [String] = [version]
}
