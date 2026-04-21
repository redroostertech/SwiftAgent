import Foundation
import MLXLMCommon

/// How a given model family spells tool calls on the wire.
///
/// MLX's tokenizer + chat template already parse tool calls *into*
/// structured `Generation.toolCall(ToolCall)` events on the way in, so
/// consumers rarely need a forward parser. The reverse direction —
/// rendering a `ToolCall` back into the raw text the model would have
/// emitted — is still needed when we replay a multi-turn conversation
/// into the next inference (the assistant's tool call has to be in the
/// history as text, not as a structured event).
///
/// Dialects are stateless value types. Host apps declare which dialect
/// a given `ModelConfiguration` speaks; everything downstream is dialect-
/// agnostic.
public protocol ToolCallDialect: Sendable {
    /// Human-readable identifier, used for logs and variant declaration.
    var name: String { get }

    /// Format a tool call back into the raw text the model would have
    /// emitted. Returns `nil` if the arguments can't be serialized to
    /// JSON (shouldn't happen in practice with MLX's structured calls).
    func synthesize(_ toolCall: ToolCall) -> String?
}

/// Hermes tool-call format — `<tool_call>{"name": "...", "arguments": {...}}</tool_call>`.
///
/// Used by the Qwen family (Qwen2.5, Qwen3) and other models trained on
/// the Hermes tool-calling dataset. This is the de-facto on-device format
/// for open-weight models that ship with tool-calling chat templates.
public struct HermesToolCallDialect: ToolCallDialect {
    public let name = "hermes"

    public init() {}

    public func synthesize(_ toolCall: ToolCall) -> String? {
        let argsObject = toolCall.function.arguments.mapValues { $0.anyValue }
        guard
            let argsData = try? JSONSerialization.data(
                withJSONObject: argsObject,
                options: [.sortedKeys]
            ),
            let argsString = String(data: argsData, encoding: .utf8)
        else {
            return nil
        }
        return "<tool_call>\n{\"name\": \"\(toolCall.function.name)\", \"arguments\": \(argsString)}\n</tool_call>"
    }
}
