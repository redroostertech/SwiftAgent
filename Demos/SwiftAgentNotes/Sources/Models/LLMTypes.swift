import Foundation
import SwiftAgentCore

/// Request body sent to the llama.cpp OpenAI-compatible
/// `/v1/chat/completions` endpoint.
struct LLMRequest: Encodable {
    /// The model identifier (e.g. `"qwen3.5"`).
    let model: String

    /// The conversation history including system, user, assistant,
    /// and tool-result messages.
    let messages: [LLMMessage]

    /// The tool catalog in OpenAI function-calling format, or `nil`
    /// if no tools are available.
    let tools: [JSONValue]?

    /// Tool selection strategy. `"auto"` lets the model decide.
    let tool_choice: String?
}

/// A single message in the LLM conversation history.
///
/// Supports all four OpenAI message roles: `system`, `user`,
/// `assistant` (with optional `tool_calls`), and `tool` (with a
/// `tool_call_id` linking it to the call it answers).
struct LLMMessage: Codable {
    /// The role: `"system"`, `"user"`, `"assistant"`, or `"tool"`.
    let role: String

    /// Text content of the message. `nil` for assistant messages that
    /// contain only tool calls.
    var content: String?

    /// Tool calls the assistant wants to make. Only present on
    /// assistant messages when the model chose to invoke tools.
    var tool_calls: [LLMToolCall]?

    /// The ID of the tool call this message is responding to. Only
    /// present on `"tool"` role messages.
    var tool_call_id: String?
}

/// A single tool invocation requested by the LLM.
struct LLMToolCall: Codable {
    /// Unique identifier for this call, used to match the tool result
    /// back to the request.
    let id: String

    /// Always `"function"` for function-calling tools.
    let type: String

    /// The function name and serialized arguments.
    let function: LLMToolCallFunction
}

/// The function name and JSON-encoded arguments string from a tool call.
struct LLMToolCallFunction: Codable {
    /// The tool name to invoke (matches an MCP tool name).
    let name: String

    /// JSON-encoded string of the arguments object.
    let arguments: String
}

/// Response from the llama.cpp `/v1/chat/completions` endpoint.
struct LLMResponse: Decodable {
    /// The list of completion choices (typically one).
    let choices: [LLMChoice]

    /// The model identifier that produced this response.
    let model: String?
}

/// A single completion choice from the LLM response.
struct LLMChoice: Decodable {
    /// The assistant's message, potentially containing tool calls.
    let message: LLMChoiceMessage
}

/// The message payload inside a completion choice.
struct LLMChoiceMessage: Decodable {
    /// The role (always `"assistant"` in a choice).
    let role: String

    /// Text content, or `nil` if the assistant only made tool calls.
    var content: String?

    /// Tool calls the assistant wants to make.
    var tool_calls: [LLMToolCall]?

    /// Convert to an ``LLMMessage`` for appending to conversation history.
    func toLLMMessage() -> LLMMessage {
        LLMMessage(role: role, content: content, tool_calls: tool_calls)
    }
}
