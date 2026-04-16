import Foundation

/// Canonical JSON-RPC method names used by the AppMCP protocol.
///
/// Collected here as string constants so transports, routers, and tests
/// can reference them without typos and so additions stay visible in a
/// single place.
public enum MCPMethod {
    // MARK: Lifecycle

    /// Initial handshake sent by clients; the very first call on a new
    /// connection.
    public static let initialize = "initialize"

    /// Notification sent by clients after they have finished processing
    /// the initialize result and are ready to use the server.
    public static let initialized = "notifications/initialized"

    /// Request sent by clients to signal that the session is ending.
    public static let shutdown = "shutdown"

    /// Lightweight health-check request. Returns an empty result.
    public static let ping = "ping"

    // MARK: Tools

    /// Request the full catalog of tools the server offers.
    public static let listTools = "tools/list"

    /// Invoke one of the tools from the catalog.
    public static let callTool = "tools/call"

    /// Notification emitted when the tool catalog changes at runtime.
    public static let toolsListChanged = "notifications/tools/list_changed"

    // MARK: Resources

    /// Request the full catalog of resources the server offers.
    public static let listResources = "resources/list"

    /// Read the contents of a specific resource by URI.
    public static let readResource = "resources/read"

    /// Notification emitted when the resource catalog changes at runtime.
    public static let resourcesListChanged = "notifications/resources/list_changed"

    // MARK: Prompts

    /// Request the full catalog of prompts the server offers.
    public static let listPrompts = "prompts/list"

    /// Fetch a specific prompt by name.
    public static let getPrompt = "prompts/get"

    // MARK: Observability

    /// Notification used by servers to emit log messages to clients.
    public static let logMessage = "notifications/message"

    /// Notification used by either side to cancel an in-flight request.
    public static let cancelled = "notifications/cancelled"
}
