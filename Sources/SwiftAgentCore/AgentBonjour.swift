import Foundation

/// Constants for AppMCP's Bonjour / DNS-SD advertisement.
///
/// Centralized in the core module so that server (`NetworkServerTransport`)
/// and client (`AgentServiceBrowser`) both speak the same service type
/// and TXT record schema without crossing module boundaries.
public enum AgentBonjour {
    /// The DNS-SD service type AppMCP advertises.
    ///
    /// Apps that embed the ``AgentServer`` network transport must add
    /// this exact string to their `NSBonjourServices` array in
    /// `Info.plist`; likewise for agent apps that browse.
    public static let serviceType = "_appmcp._tcp"

    /// Keys used in the Bonjour TXT record AppMCP advertises alongside
    /// the service. All values are strings so the record stays
    /// DNS-SD-clean.
    public enum TXTKey {
        /// The AppMCP protocol version the server speaks. Matches
        /// ``AgentProtocol/version``.
        public static let version = "v"
        /// Human-readable server name.
        public static let name = "name"
        /// Semantic version of the server implementation.
        public static let serverVersion = "version"
        /// Apple bundle identifier of the hosting app, when applicable.
        public static let bundle = "bundle"
    }
}
