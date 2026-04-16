import Foundation
import SwiftAgent
import SwiftAgentHTTPClient
import Observation

/// Manages the in-process agent server, local tool catalog, and optional
/// remote MCP server connection.
///
/// `NoteAgentManager` owns both sides of the agent surface:
///
/// 1. **Local tools** — registered with an ``AgentServer`` and accessed via
///    ``AgentClient`` over in-process transports.
/// 2. **Remote tools** — fetched from an external MCP server entered by
///    the user in Settings, connected via ``HTTPClientTransport``.
@Observable
final class NoteAgentManager: @unchecked Sendable {

    // MARK: - Local state

    /// Tool descriptors from the local in-process server.
    private(set) var localTools: [MCPToolDescriptor] = []

    /// Whether the local agent has completed initialization.
    private(set) var isReady: Bool = false

    /// Error from setup or invocation.
    private(set) var errorMessage: String?

    // MARK: - Remote state

    /// Tool descriptors from a connected remote MCP server.
    private(set) var remoteTools: [MCPToolDescriptor] = []

    /// Whether a remote server connection is active.
    private(set) var isRemoteConnected: Bool = false

    /// Status string for the remote connection.
    private(set) var remoteStatus: String = "Not connected"

    /// Error from the remote connection attempt.
    private(set) var remoteError: String?

    // MARK: - Persisted settings

    /// The remote MCP server URL, persisted via UserDefaults.
    @ObservationIgnored
    var remoteServerURL: String {
        get { UserDefaults.standard.string(forKey: "notesRemoteServerURL") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "notesRemoteServerURL") }
    }

    // MARK: - Agent panel state

    /// The currently selected tool name.
    var selectedToolName: String?

    /// User-entered argument values keyed by parameter name.
    var argumentValues: [String: String] = [:]

    /// The most recent invocation result text.
    var resultText: String?

    /// Whether the result is an error.
    var resultIsError: Bool = false

    /// Whether an invocation is in flight.
    var isInvoking: Bool = false

    // MARK: - All tools (merged)

    /// Combined local + remote tool catalog for the agent panel.
    var allTools: [MCPToolDescriptor] { localTools + remoteTools }

    // MARK: - Private

    private let server: AgentServer
    private var localClient: AgentClient?
    private var remoteClient: AgentClient?
    private var remoteTransport: HTTPClientTransport?

    init() {
        self.server = AgentServer(
            info: MCPImplementation(
                name: "SwiftAgent Notes",
                version: "1.0.0",
                bundleIdentifier: Bundle.main.bundleIdentifier
            ),
            instructions: "Use these tools to create, read, update, delete, and search notes."
        )
    }

    // MARK: - Local setup

    /// Register all note tools and start the in-process transport.
    func start() async {
        do {
            try await server.register(CreateNoteTool.asAgentTool())
            try await server.register(ListNotesTool.asAgentTool())
            try await server.register(SearchNotesTool.asAgentTool())
            try await server.register(GetNoteTool.asAgentTool())
            try await server.register(UpdateNoteTool.asAgentTool())
            try await server.register(DeleteNoteTool.asAgentTool())

            let serverTransport = InProcessServerTransport()
            try await server.start(transport: serverTransport)

            let clientTransport = InProcessClientTransport { request in
                await serverTransport.deliver(request)
            }
            let client = AgentClient(
                info: MCPImplementation(name: "Notes Client", version: "1.0.0"),
                transport: clientTransport
            )
            try await client.initialize()
            self.localClient = client

            let descriptors = try await client.listTools()
            self.localTools = descriptors
            if let first = descriptors.first {
                self.selectedToolName = first.name
            }
            self.isReady = true
        } catch {
            self.errorMessage = "Agent setup failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Remote connection

    /// Connect to a remote MCP server at the stored URL.
    func connectRemote() async {
        guard !remoteServerURL.isEmpty,
              let url = URL(string: remoteServerURL) else {
            remoteError = "Invalid URL"
            return
        }

        await disconnectRemote()

        remoteStatus = "Connecting..."
        remoteError = nil

        do {
            let transport = HTTPClientTransport(url: url)
            self.remoteTransport = transport

            let client = AgentClient(
                info: MCPImplementation(name: "Notes Remote Client", version: "1.0.0"),
                transport: transport
            )
            try await client.initialize()
            self.remoteClient = client

            let tools = try await client.listTools()
            self.remoteTools = tools
            self.isRemoteConnected = true
            self.remoteStatus = "Connected — \(tools.count) tools"
        } catch {
            self.remoteError = error.localizedDescription
            self.remoteStatus = "Failed"
            self.isRemoteConnected = false
        }
    }

    /// Disconnect from the remote MCP server.
    func disconnectRemote() async {
        if let client = remoteClient {
            await client.close()
        }
        remoteClient = nil
        remoteTransport = nil
        remoteTools = []
        isRemoteConnected = false
        remoteStatus = "Not connected"
        remoteError = nil
    }

    // MARK: - Tool selection

    /// The descriptor for the currently selected tool.
    var selectedTool: MCPToolDescriptor? {
        allTools.first { $0.name == selectedToolName }
    }

    /// Whether the selected tool is a remote tool.
    var isSelectedToolRemote: Bool {
        guard let name = selectedToolName else { return false }
        return remoteTools.contains { $0.name == name }
    }

    /// Schema properties for the selected tool, for form generation.
    var selectedToolProperties: [(name: String, schema: MCPSchema, isRequired: Bool)] {
        guard let tool = selectedTool,
              let properties = tool.inputSchema.properties else {
            return []
        }
        let required = Set(tool.inputSchema.required ?? [])
        return properties
            .sorted { $0.key < $1.key }
            .map { (name: $0.key, schema: $0.value, isRequired: required.contains($0.key)) }
    }

    /// Update the selected tool and reset argument values.
    func selectTool(_ toolName: String) {
        selectedToolName = toolName
        argumentValues = [:]
        resultText = nil
        resultIsError = false
    }

    // MARK: - Invocation

    /// Invoke the selected tool with the current argument values.
    func invoke() async {
        guard let tool = selectedTool else { return }

        let client: AgentClient?
        if isSelectedToolRemote {
            client = remoteClient
        } else {
            client = localClient
        }
        guard let client else { return }

        isInvoking = true
        resultText = nil
        resultIsError = false
        defer { isInvoking = false }

        var args: [String: JSONValue] = [:]
        let properties = tool.inputSchema.properties ?? [:]
        for (key, value) in argumentValues {
            guard !value.isEmpty else { continue }
            if let propSchema = properties[key] {
                switch propSchema.type {
                case .boolean:
                    args[key] = .bool(["true", "yes", "1"].contains(value.lowercased()))
                case .integer:
                    if let v = Int64(value) { args[key] = .int(v) }
                case .number:
                    if let v = Double(value) { args[key] = .double(v) }
                default:
                    args[key] = .string(value)
                }
            } else {
                args[key] = .string(value)
            }
        }

        do {
            let result = try await client.callTool(
                name: tool.name,
                arguments: args.isEmpty ? nil : .object(args)
            )
            let texts = result.content.compactMap { content -> String? in
                if case .text(let text) = content { return text }
                return nil
            }
            resultText = texts.joined(separator: "\n")
            resultIsError = result.isError
        } catch {
            resultText = error.localizedDescription
            resultIsError = true
        }
    }
}
