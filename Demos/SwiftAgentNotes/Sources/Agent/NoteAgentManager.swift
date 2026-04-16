import Foundation
import SwiftAgent
import SwiftAgentHTTPClient
import SwiftAgentOpenAI
import Observation

/// Manages the in-process agent server, optional remote MCP connection,
/// and the AI chat loop that connects a local LLM (llama.cpp) to tools.
@Observable
final class NoteAgentManager: @unchecked Sendable {

    // MARK: - Local state

    /// Tool descriptors from the local in-process server.
    private(set) var localTools: [MCPToolDescriptor] = []

    /// Whether the local agent has completed initialization.
    private(set) var isReady: Bool = false

    /// Error from setup or invocation.
    private(set) var errorMessage: String?

    // MARK: - Remote MCP state

    /// Tool descriptors from a connected remote MCP server.
    private(set) var remoteTools: [MCPToolDescriptor] = []

    /// Whether a remote server connection is active.
    private(set) var isRemoteConnected: Bool = false

    /// Status string for the remote connection.
    private(set) var remoteStatus: String = "Not connected"

    /// Error from the remote connection attempt.
    private(set) var remoteError: String?

    // MARK: - AI Chat state

    /// The conversation history shown in the chat view.
    private(set) var chatMessages: [ChatBubble] = []

    /// Whether the LLM is currently processing.
    private(set) var isChatting: Bool = false

    // MARK: - Persisted settings

    @ObservationIgnored
    var remoteServerURL: String {
        get { UserDefaults.standard.string(forKey: "notesRemoteServerURL") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "notesRemoteServerURL") }
    }

    @ObservationIgnored
    var llmURL: String {
        get { UserDefaults.standard.string(forKey: "notesLLMURL") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "notesLLMURL") }
    }

    // MARK: - Manual tool panel state

    var selectedToolName: String?
    var argumentValues: [String: String] = [:]
    var resultText: String?
    var resultIsError: Bool = false
    var isInvoking: Bool = false
    var allTools: [MCPToolDescriptor] { localTools + remoteTools }

    // MARK: - Private

    private let server: AgentServer
    private var localClient: AgentClient?
    private var remoteClient: AgentClient?
    private var remoteTransport: HTTPClientTransport?
    private var llmConversation: [LLMMessage] = []

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

    // MARK: - Remote MCP connection

    func connectRemote() async {
        guard !remoteServerURL.isEmpty, let url = URL(string: remoteServerURL) else {
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

    func disconnectRemote() async {
        if let client = remoteClient { await client.close() }
        remoteClient = nil
        remoteTransport = nil
        remoteTools = []
        isRemoteConnected = false
        remoteStatus = "Not connected"
        remoteError = nil
    }

    // MARK: - Manual tool panel

    var selectedTool: MCPToolDescriptor? {
        allTools.first { $0.name == selectedToolName }
    }

    var isSelectedToolRemote: Bool {
        guard let name = selectedToolName else { return false }
        return remoteTools.contains { $0.name == name }
    }

    var selectedToolProperties: [(name: String, schema: MCPSchema, isRequired: Bool)] {
        guard let tool = selectedTool, let properties = tool.inputSchema.properties else { return [] }
        let required = Set(tool.inputSchema.required ?? [])
        return properties.sorted { $0.key < $1.key }
            .map { (name: $0.key, schema: $0.value, isRequired: required.contains($0.key)) }
    }

    func selectTool(_ toolName: String) {
        selectedToolName = toolName
        argumentValues = [:]
        resultText = nil
        resultIsError = false
    }

    func invoke() async {
        guard let tool = selectedTool else { return }
        let client: AgentClient? = isSelectedToolRemote ? remoteClient : localClient
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
                case .boolean: args[key] = .bool(["true", "yes", "1"].contains(value.lowercased()))
                case .integer: if let v = Int64(value) { args[key] = .int(v) }
                case .number: if let v = Double(value) { args[key] = .double(v) }
                default: args[key] = .string(value)
                }
            } else {
                args[key] = .string(value)
            }
        }

        do {
            let result = try await client.callTool(name: tool.name, arguments: args.isEmpty ? nil : .object(args))
            let texts = result.content.compactMap { c -> String? in
                if case .text(let t) = c { return t }
                return nil
            }
            resultText = texts.joined(separator: "\n")
            resultIsError = result.isError
        } catch {
            resultText = error.localizedDescription
            resultIsError = true
        }
    }

    // MARK: - AI Chat (LLM + tool calling)

    /// Send a natural language prompt to the LLM and let it decide which
    /// tools to call. The full agentic loop runs: prompt → LLM → tool
    /// calls → results → LLM → final response with signature.
    func chat(prompt: String) async {
        guard !llmURL.isEmpty, let url = URL(string: llmURL) else {
            chatMessages.append(ChatBubble(
                role: .system,
                text: "Set your LLM URL in Settings first (e.g. http://10.0.0.72:8080/v1/chat/completions)"
            ))
            return
        }

        chatMessages.append(ChatBubble(role: .user, text: prompt))
        isChatting = true
        defer { isChatting = false }

        let startTime = ContinuousClock.now

        // Initialize conversation if empty
        if llmConversation.isEmpty {
            llmConversation.append(LLMMessage(
                role: "system",
                content: "You are a helpful notes assistant. Use the available tools to manage the user's notes. Be concise."
            ))
        }
        llmConversation.append(LLMMessage(role: "user", content: prompt))

        // Build OpenAI-format tools from all available tools
        let openAITools = OpenAIToolExport.export(allTools)

        var modelName = "unknown"
        var toolsUsed: [String] = []
        var iterations = 5

        while iterations > 0 {
            iterations -= 1

            let requestBody = LLMRequest(
                model: "qwen3.5",
                messages: llmConversation,
                tools: openAITools.arrayValue,
                tool_choice: "auto"
            )

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(requestBody)
            request.timeoutInterval = 120

            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                let response = try JSONDecoder().decode(LLMResponse.self, from: data)
                modelName = response.model ?? "unknown"

                guard let choice = response.choices.first else {
                    chatMessages.append(ChatBubble(role: .system, text: "No response from LLM."))
                    break
                }

                llmConversation.append(choice.message.toLLMMessage())

                guard let calls = choice.message.tool_calls, !calls.isEmpty else {
                    // Final response — no more tool calls
                    let elapsed = ContinuousClock.now - startTime
                    let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                    let text = choice.message.content ?? "(no response)"
                    var signature = "Performed by \(modelName)"
                    if !toolsUsed.isEmpty {
                        signature += " using \(toolsUsed.joined(separator: ", "))"
                    }
                    signature += String(format: " in %.1fs", seconds)
                    chatMessages.append(ChatBubble(role: .assistant, text: text, signature: signature))
                    break
                }

                // Execute tool calls
                for call in calls {
                    toolsUsed.append(call.function.name)
                    chatMessages.append(ChatBubble(role: .tool, text: "Calling \(call.function.name)..."))

                    var args: JSONValue = .object([:])
                    if let argData = call.function.arguments.data(using: .utf8),
                       let parsed = try? JSONDecoder.swiftAgent.decode(JSONValue.self, from: argData) {
                        args = parsed
                    }

                    // Route to the right client
                    let isRemote = remoteTools.contains { $0.name == call.function.name }
                    let client: AgentClient? = isRemote ? remoteClient : localClient

                    var resultText = "Error: no client available"
                    if let client {
                        do {
                            let result = try await client.callTool(name: call.function.name, arguments: args)
                            let texts = result.content.compactMap { c -> String? in
                                if case .text(let t) = c { return t }
                                if case .json(let j) = c, let d = try? JSONEncoder.swiftAgent.encode(j) {
                                    return String(data: d, encoding: .utf8)
                                }
                                return nil
                            }
                            resultText = texts.joined(separator: "\n")
                        } catch {
                            resultText = "Error: \(error.localizedDescription)"
                        }
                    }

                    llmConversation.append(LLMMessage(role: "tool", content: resultText, tool_call_id: call.id))
                }
            } catch {
                chatMessages.append(ChatBubble(role: .system, text: "LLM error: \(error.localizedDescription)"))
                break
            }
        }
    }

    /// Clear the chat history and LLM conversation context.
    func clearChat() {
        chatMessages = []
        llmConversation = []
    }
}

