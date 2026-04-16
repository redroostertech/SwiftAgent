import Foundation
import SwiftUI
import SwiftAgent
import SwiftAgentHTTPClient

/// Manages the local agent server and optional remote MCP client connection.
///
/// `TaskAgentManager` owns both sides of the agent surface:
///
/// 1. **Local tools** — registered with an in-process ``AgentServer`` and
///    accessed via an ``AgentClient`` over ``InProcessClientTransport``.
/// 2. **Remote tools** — fetched from an external MCP server entered by
///    the user in Settings, connected via ``HTTPClientTransport``.
///
/// The manager exposes a merged tool catalog that the ``AgentPanelView``
/// renders, and provides methods to invoke tools on either side.
@Observable
final class TaskAgentManager: @unchecked Sendable {

    // MARK: - Published state

    /// Tool descriptors from the local in-process server.
    private(set) var localTools: [MCPToolDescriptor] = []

    /// Tool descriptors from a connected remote MCP server.
    private(set) var remoteTools: [MCPToolDescriptor] = []

    /// Whether a remote server connection is currently active.
    private(set) var isRemoteConnected: Bool = false

    /// Human-readable status of the remote connection.
    private(set) var remoteStatus: String = "Not connected"

    /// The last error encountered, if any.
    private(set) var lastError: String?

    // MARK: - Persisted settings

    /// The user-entered remote MCP server URL, persisted via AppStorage.
    @ObservationIgnored
    var remoteServerURL: String {
        get { UserDefaults.standard.string(forKey: "remoteServerURL") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "remoteServerURL") }
    }

    // MARK: - Private state

    /// The local agent server hosting registered tools.
    private let server: AgentServer

    /// The in-process client used to invoke local tools.
    private var localClient: AgentClient?

    /// The remote client used to invoke tools on an external MCP server.
    private var remoteClient: AgentClient?

    // MARK: - Initialization

    /// Create a new task agent manager and set up the local server.
    init() {
        self.server = AgentServer(
            info: MCPImplementation(
                name: "SwiftAgent Tasks",
                version: "1.0.0",
                bundleIdentifier: Bundle.main.bundleIdentifier
            ),
            instructions: "Task management tools for creating, reading, updating, and deleting tasks and projects."
        )
    }

    // MARK: - Setup

    /// Register all local tools and start the in-process server.
    ///
    /// Call this once from the app entry point after the model container
    /// has been configured.
    func setup() async {
        do {
            try await server.register(CreateTaskTool.asAgentTool())
            try await server.register(ListTasksTool.asAgentTool())
            try await server.register(GetTaskTool.asAgentTool())
            try await server.register(CompleteTaskTool.asAgentTool())
            try await server.register(UpdateTaskTool.asAgentTool())
            try await server.register(DeleteTaskTool.asAgentTool())
            try await server.register(ListProjectsTool.asAgentTool())

            // Start an in-process transport so we can call our own tools.
            let serverTransport = InProcessServerTransport()
            try await server.start(transport: serverTransport)

            let clientTransport = InProcessClientTransport { request in
                await serverTransport.deliver(request)
            }
            let client = AgentClient(
                info: MCPImplementation(name: "Tasks App", version: "1.0"),
                transport: clientTransport
            )
            try await client.initialize()
            self.localClient = client

            // Fetch local tool descriptors.
            let tools = try await client.listTools()
            await MainActor.run {
                self.localTools = tools
            }
        } catch {
            await MainActor.run {
                self.lastError = "Local setup failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Remote connection

    /// Connect to a remote MCP server at the given URL string.
    ///
    /// - Parameter urlString: The server's MCP endpoint URL.
    func connectRemote(urlString: String) async {
        // Disconnect any existing connection first.
        await disconnectRemote()

        guard let url = URL(string: urlString), !urlString.isEmpty else {
            await MainActor.run {
                self.remoteStatus = "Invalid URL"
                self.lastError = "Invalid server URL: \(urlString)"
            }
            return
        }

        await MainActor.run {
            self.remoteStatus = "Connecting..."
            self.lastError = nil
        }

        do {
            let transport = HTTPClientTransport(url: url)
            let client = AgentClient(
                info: MCPImplementation(name: "SwiftAgent Tasks", version: "1.0"),
                transport: transport
            )
            try await client.initialize()
            let tools = try await client.listTools()

            self.remoteClient = client
            self.remoteServerURL = urlString

            await MainActor.run {
                self.remoteTools = tools
                self.isRemoteConnected = true
                self.remoteStatus = "Connected (\(tools.count) tools)"
            }
        } catch {
            await MainActor.run {
                self.remoteTools = []
                self.isRemoteConnected = false
                self.remoteStatus = "Connection failed"
                self.lastError = error.localizedDescription
            }
        }
    }

    /// Disconnect from the remote MCP server.
    func disconnectRemote() async {
        if let client = remoteClient {
            await client.close()
            self.remoteClient = nil
        }
        await MainActor.run {
            self.remoteTools = []
            self.isRemoteConnected = false
            self.remoteStatus = "Not connected"
        }
    }

    // MARK: - Tool invocation

    /// Invoke a local tool by name with the given arguments.
    ///
    /// - Parameters:
    ///   - name: The tool's machine-readable name.
    ///   - arguments: A dictionary of argument name-value pairs.
    /// - Returns: The tool result as a displayable string.
    func invokeLocalTool(name: String, arguments: [String: String]) async throws -> String {
        guard let client = localClient else {
            throw AgentManagerError.notConnected
        }

        var jsonArgs: [String: JSONValue] = [:]
        for (key, value) in arguments {
            if value.lowercased() == "true" || value.lowercased() == "false" {
                jsonArgs[key] = .bool(value.lowercased() == "true")
            } else {
                jsonArgs[key] = .string(value)
            }
        }

        let result = try await client.callTool(
            name: name,
            arguments: .object(jsonArgs)
        )
        return result.content.compactMap { content in
            switch content {
            case .text(let text): return text
            case .json(let value): return "\(value)"
            default: return nil
            }
        }.joined(separator: "\n")
    }

    /// Invoke a remote tool by name with the given arguments.
    ///
    /// - Parameters:
    ///   - name: The tool's machine-readable name.
    ///   - arguments: A dictionary of argument name-value pairs.
    /// - Returns: The tool result as a displayable string.
    func invokeRemoteTool(name: String, arguments: [String: String]) async throws -> String {
        guard let client = remoteClient else {
            throw AgentManagerError.notConnected
        }

        var jsonArgs: [String: JSONValue] = [:]
        for (key, value) in arguments {
            if value.lowercased() == "true" || value.lowercased() == "false" {
                jsonArgs[key] = .bool(value.lowercased() == "true")
            } else {
                jsonArgs[key] = .string(value)
            }
        }

        let result = try await client.callTool(
            name: name,
            arguments: .object(jsonArgs)
        )
        return result.content.compactMap { content in
            switch content {
            case .text(let text): return text
            case .json(let value): return "\(value)"
            default: return nil
            }
        }.joined(separator: "\n")
    }
}

/// Errors specific to ``TaskAgentManager`` operations.
enum AgentManagerError: LocalizedError {
    /// No agent client is connected.
    case notConnected

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Agent client is not connected."
        }
    }
}
