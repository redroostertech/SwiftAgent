import Foundation
import SwiftAgent
import Observation

/// Manages the in-process agent server and client lifecycle.
///
/// `NoteAgentManager` owns an ``AgentServer`` with all six note tools
/// registered, wired to an ``AgentClient`` via in-process transports.
/// The ``AgentPanelView`` binds to this class to list available tools,
/// collect arguments through auto-generated forms, invoke tools, and
/// display results.
@Observable
final class NoteAgentManager {
    /// The tool catalog fetched from the server after initialization.
    var tools: [MCPToolDescriptor] = []

    /// The currently selected tool name in the agent panel.
    var selectedToolName: String?

    /// User-entered argument values keyed by parameter name.
    var argumentValues: [String: String] = [:]

    /// The most recent tool invocation result text.
    var resultText: String?

    /// Whether the result represents an error.
    var resultIsError: Bool = false

    /// Whether a tool invocation is currently in flight.
    var isInvoking: Bool = false

    /// Whether the agent has completed its initialization handshake.
    var isReady: Bool = false

    /// Error message from setup or tool invocation, if any.
    var errorMessage: String?

    /// The server instance hosting the note tools.
    private let server: AgentServer

    /// The client used to call tools on the server.
    private var client: AgentClient?

    /// Create a new agent manager and prepare the server with all tools.
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

    /// Register all note tools and start the in-process transport.
    ///
    /// Call this once at app launch after ``NoteStore`` has been configured.
    func start() async {
        do {
            // Register all six tools with the server.
            try await server.register(CreateNoteTool.asAgentTool())
            try await server.register(ListNotesTool.asAgentTool())
            try await server.register(SearchNotesTool.asAgentTool())
            try await server.register(GetNoteTool.asAgentTool())
            try await server.register(UpdateNoteTool.asAgentTool())
            try await server.register(DeleteNoteTool.asAgentTool())

            // Wire up in-process transports.
            let serverTransport = InProcessServerTransport()
            try await server.start(transport: serverTransport)

            let clientTransport = InProcessClientTransport { request in
                await serverTransport.deliver(request)
            }
            let agentClient = AgentClient(
                info: MCPImplementation(
                    name: "SwiftAgent Notes Client",
                    version: "1.0.0"
                ),
                transport: clientTransport
            )
            try await agentClient.initialize()
            self.client = agentClient

            // Fetch the tool catalog.
            let descriptors = try await agentClient.listTools()
            self.tools = descriptors
            if let first = descriptors.first {
                self.selectedToolName = first.name
            }
            self.isReady = true
        } catch {
            self.errorMessage = "Agent setup failed: \(error.localizedDescription)"
        }
    }

    /// The descriptor for the currently selected tool, if any.
    var selectedTool: MCPToolDescriptor? {
        tools.first { $0.name == selectedToolName }
    }

    /// The ordered list of property entries from the selected tool's
    /// input schema, suitable for rendering form fields.
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
    ///
    /// - Parameter toolName: The machine name of the tool to select.
    func selectTool(_ toolName: String) {
        selectedToolName = toolName
        argumentValues = [:]
        resultText = nil
        resultIsError = false
    }

    /// Invoke the selected tool with the current argument values.
    ///
    /// Builds a ``JSONValue`` object from ``argumentValues`` and calls
    /// the tool through the agent client. The result is stored in
    /// ``resultText``.
    func invoke() async {
        guard let client, let tool = selectedTool else { return }

        isInvoking = true
        resultText = nil
        resultIsError = false
        defer { isInvoking = false }

        // Build the arguments object, coercing types based on the schema.
        var args: [String: JSONValue] = [:]
        let properties = tool.inputSchema.properties ?? [:]
        for (key, value) in argumentValues {
            guard !value.isEmpty else { continue }
            if let propSchema = properties[key] {
                switch propSchema.type {
                case .boolean:
                    let boolVal = ["true", "yes", "1"].contains(value.lowercased())
                    args[key] = .bool(boolVal)
                case .integer:
                    if let intVal = Int64(value) {
                        args[key] = .int(intVal)
                    }
                case .number:
                    if let numVal = Double(value) {
                        args[key] = .double(numVal)
                    }
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
