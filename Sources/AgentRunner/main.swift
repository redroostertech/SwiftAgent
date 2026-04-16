import Foundation
import SwiftAgentCore
import SwiftAgentClient
import SwiftAgentHTTPClient
import SwiftAgentOpenAI

// ─────────────────────────────────────────────────────────────
// AgentRunner — Full agentic loop: LLM ↔ SwiftAgent tools
//
// Connects to:
//   1. An MCP server (MCPTestServer) for tools
//   2. A llama.cpp server (Qwen3.5-9B) for LLM inference
//
// The LLM decides which tool to call. SwiftAgent dispatches it.
// The result goes back to the LLM. The response includes a
// signature with model name and total duration.
//
// Usage:
//   swift run MCPTestServer        (Terminal 1, port 9090)
//   swift run AgentRunner          (Terminal 2)
// ─────────────────────────────────────────────────────────────

let llmURL = URL(string: ProcessInfo.processInfo.environment["LLM_URL"]
    ?? "http://127.0.0.1:8080/v1/chat/completions")!
let mcpURL = URL(string: ProcessInfo.processInfo.environment["MCP_URL"]
    ?? "http://localhost:9090/mcp")!

// MARK: - OpenAI-compatible API types

struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let tools: [JSONValue]?
    let tool_choice: String?
}

struct ChatMessage: Codable {
    let role: String
    var content: String?
    var tool_calls: [ToolCall]?
    var tool_call_id: String?
}

struct ToolCall: Codable {
    let id: String
    let type: String
    let function: ToolCallFunction
}

struct ToolCallFunction: Codable {
    let name: String
    let arguments: String
}

struct ChatResponse: Decodable {
    let choices: [Choice]
    let model: String?
    let usage: Usage?

    struct Choice: Decodable {
        let message: ChatMessage
        let finish_reason: String?
    }

    struct Usage: Decodable {
        let prompt_tokens: Int?
        let completion_tokens: Int?
        let total_tokens: Int?
    }
}

// MARK: - MCP client setup

print("Connecting to MCP server at \(mcpURL)...")
let mcpTransport = HTTPClientTransport(url: mcpURL)
let mcpClient = AgentClient(
    info: MCPImplementation(name: "AgentRunner", version: "1.0.0"),
    transport: mcpTransport
)

do {
    try await mcpClient.initialize()
} catch {
    print("Failed to connect to MCP server: \(error.localizedDescription)")
    print("Make sure MCPTestServer is running: swift run MCPTestServer")
    Foundation.exit(1)
}

let tools = try await mcpClient.listTools()
let openAITools = OpenAIToolExport.export(tools)

print("Connected. \(tools.count) tools available:")
for tool in tools {
    print("  • \(tool.name) — \(tool.description)")
}

// MARK: - Chat loop

let systemPrompt = """
You are a helpful assistant with access to tools. When the user asks \
something that a tool can help with, call the appropriate tool. After \
receiving the tool result, synthesize a natural response for the user. \
Be concise.
"""

var conversationHistory: [ChatMessage] = [
    ChatMessage(role: "system", content: systemPrompt)
]

print("""

┌──────────────────────────────────────────────────┐
│  AgentRunner — Qwen3.5-9B + SwiftAgent tools     │
│                                                  │
│  LLM: \(llmURL.absoluteString)
│  MCP: \(mcpURL.absoluteString)
│  Tools: \(tools.map(\.name).joined(separator: ", "))
│                                                  │
│  Type a message and press Enter.                 │
│  Type 'quit' to exit.                            │
└──────────────────────────────────────────────────┘
""")

let session = URLSession(configuration: .default)

while true {
    print("\n\u{001B}[36mYou:\u{001B}[0m ", terminator: "")
    guard let input = readLine(), !input.isEmpty else { continue }
    if input.lowercased() == "quit" { break }

    let startTime = ContinuousClock.now

    conversationHistory.append(ChatMessage(role: "user", content: input))

    var modelName = "unknown"
    var totalToolCalls = 0
    var toolsUsed: [String] = []

    // Agentic loop: keep calling the LLM until it stops requesting tools
    var iterationLimit = 5
    while iterationLimit > 0 {
        iterationLimit -= 1

        let chatRequest = ChatRequest(
            model: "qwen3.5",
            messages: conversationHistory,
            tools: openAITools.arrayValue,
            tool_choice: "auto"
        )

        var urlRequest = URLRequest(url: llmURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(chatRequest)
        urlRequest.timeoutInterval = 120

        let (data, _) = try await session.data(for: urlRequest)

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        modelName = chatResponse.model ?? "unknown"

        guard let choice = chatResponse.choices.first else {
            print("No response from LLM.")
            break
        }

        let assistantMessage = choice.message

        // Add assistant message to history
        conversationHistory.append(assistantMessage)

        // Check if the LLM wants to call tools
        guard let calls = assistantMessage.tool_calls, !calls.isEmpty else {
            // No tool calls — this is the final response
            let elapsed = ContinuousClock.now - startTime
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18

            let response = assistantMessage.content ?? "(no response)"
            print("\n\u{001B}[33mAssistant:\u{001B}[0m \(response)")

            // Signature
            print("\n\u{001B}[90m─── Performed by \(modelName)", terminator: "")
            if !toolsUsed.isEmpty {
                print(" using \(toolsUsed.joined(separator: ", "))", terminator: "")
            }
            print(String(format: " in %.2fs ───\u{001B}[0m", seconds))

            break
        }

        // Execute each tool call via MCP
        for call in calls {
            totalToolCalls += 1
            toolsUsed.append(call.function.name)

            print("\u{001B}[90m  → calling \(call.function.name)...\u{001B}[0m", terminator: "")

            // Parse arguments from the LLM's JSON string
            var args: JSONValue = .object([:])
            if let argData = call.function.arguments.data(using: .utf8),
               let parsed = try? JSONDecoder.swiftAgent.decode(JSONValue.self, from: argData) {
                args = parsed
            }

            do {
                let result = try await mcpClient.callTool(
                    name: call.function.name,
                    arguments: args
                )
                let resultText = result.content.compactMap { c -> String? in
                    if case .text(let t) = c { return t }
                    if case .json(let j) = c {
                        if let d = try? JSONEncoder.swiftAgent.encode(j) {
                            return String(data: d, encoding: .utf8)
                        }
                    }
                    return nil
                }.joined(separator: "\n")

                print(" \u{001B}[32m✓\u{001B}[0m")

                conversationHistory.append(ChatMessage(
                    role: "tool",
                    content: resultText,
                    tool_call_id: call.id
                ))
            } catch {
                print(" \u{001B}[31m✗ \(error.localizedDescription)\u{001B}[0m")

                conversationHistory.append(ChatMessage(
                    role: "tool",
                    content: "Error: \(error.localizedDescription)",
                    tool_call_id: call.id
                ))
            }
        }
        // Loop back to send tool results to the LLM
    }
}

print("Goodbye.")
await mcpClient.close()
