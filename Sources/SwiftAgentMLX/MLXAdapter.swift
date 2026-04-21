import Foundation
import MLXLMCommon
import SwiftAgentCore
import SwiftAgentServer

/// Bridges an `AgentServer`'s tool surface into Apple's on-device
/// MLX Swift inference stack.
///
/// `MLXAdapter` does two things:
///
/// 1. **Tool export.** Walks the server's registered tool descriptors and
///    renders them in the OpenAI-style JSON schema shape that MLX
///    (`MLXLMCommon.UserInput.tools`) expects. Host apps pass these
///    through the chat template so Qwen (or any MLX-hosted model that
///    speaks the Hermes tool format) sees the tools natively.
/// 2. **Tool dispatch.** When `MLXLMCommon.generate` yields a structured
///    `Generation.toolCall(ToolCall)` event, the host forwards it here;
///    the adapter resolves the tool name, converts MLX's own `JSONValue`
///    arguments into SwiftAgent's `JSONValue` via a direct recursive
///    conversion (no Data round-trip), invokes the server via its
///    direct `callTool(name:arguments:)` path, and returns the
///    `MCPCallToolResult` for the next inference turn.
///
/// Tool-spec rendering is cached behind a lightweight registry version
/// stamp (tool-name list hash). Hosts that hot-register tools get fresh
/// specs automatically without paying the JSON-schema serialization cost
/// on every inference turn.
public actor MLXAdapter {
    /// The server whose tools this adapter exposes to MLX.
    public nonisolated let server: AgentServer

    private var cachedFingerprint: String = ""
    private var cachedSpecs: [[String: any Sendable]] = []

    /// Build an adapter around an existing `AgentServer`.
    public init(server: AgentServer) {
        self.server = server
    }

    // MARK: - Tool export

    /// Render every tool registered on the server as an MLX `ToolSpec`.
    ///
    /// Results are cached until the registered tool set changes. The host
    /// app passes the result as `UserInput(chat:tools:)` so the chat
    /// template can advertise tools natively.
    public func toolSpecs() async -> [[String: any Sendable]] {
        let descriptors = await server.toolDescriptors
        let fingerprint = Self.fingerprint(descriptors: descriptors)
        if fingerprint == cachedFingerprint, !cachedSpecs.isEmpty {
            return cachedSpecs
        }
        let specs = descriptors.compactMap(Self.toolSpec(from:))
        cachedFingerprint = fingerprint
        cachedSpecs = specs
        return specs
    }

    /// Invalidate the cached tool-spec rendering. Call after hot-
    /// registering tools if you want the next `toolSpecs()` to rebuild
    /// before the natural fingerprint change.
    public func invalidateToolCache() {
        cachedFingerprint = ""
        cachedSpecs = []
    }

    /// Look up a single tool by name and return its OpenAI-style spec
    /// dictionary. Used on the memory-hot path when a high-confidence
    /// classifier has already picked the only tool we need — passing a
    /// one-element tools array keeps the Qwen system prompt small.
    public func toolSpec(named name: String) async -> [String: any Sendable]? {
        let descriptors = await server.toolDescriptors
        guard let descriptor = descriptors.first(where: { $0.name == name }) else {
            return nil
        }
        return Self.toolSpec(from: descriptor)
    }

    /// Convert a single `MCPToolDescriptor` to the OpenAI-style
    /// tool-spec dict (`["type": "function", "function": {...}]`).
    ///
    /// Matches `MLXLMCommon.ToolSpec` (which is itself `[String: Any]`
    /// in the Tokenizers layer) without forcing consumers to import
    /// Tokenizers to read the return type.
    public static func toolSpec(from descriptor: MCPToolDescriptor) -> [String: any Sendable]? {
        guard let parametersAny = jsonObject(descriptor.inputSchema) as? [String: any Sendable] else {
            return nil
        }
        var function: [String: any Sendable] = [
            "name": descriptor.name,
            "description": descriptor.description,
            "parameters": parametersAny
        ]
        if let title = descriptor.title {
            function["title"] = title
        }
        return [
            "type": "function",
            "function": function
        ]
    }

    // MARK: - Tool dispatch

    /// Invoke a tool in response to an `MLXLMCommon.Generation.toolCall`
    /// event.
    ///
    /// Arguments are converted directly between MLX's `JSONValue` and
    /// SwiftAgent's `JSONValue` without a serialization round-trip.
    public func dispatch(_ toolCall: ToolCall) async throws -> MCPCallToolResult {
        let arguments = toolCall.function.arguments.mapValues(Self.convert(_:))
        return try await server.callTool(name: toolCall.function.name, arguments: arguments)
    }

    /// Convenience: render an `MCPCallToolResult` as a plain text string
    /// suitable for feeding back into the next LLM turn.
    ///
    /// Text blocks are concatenated with `\n`; JSON blocks are serialized
    /// as pretty-printed JSON. Hosts that want richer rendering (UI cards,
    /// structured displays) should inspect `result.content` directly.
    public static func stringify(_ result: MCPCallToolResult) -> String {
        var parts: [String] = []
        for block in result.content {
            switch block {
            case .text(let string):
                parts.append(string)
            case .json(let value):
                if let data = try? JSONEncoder.swiftAgent.encode(value),
                   let string = String(data: data, encoding: .utf8) {
                    parts.append(string)
                }
            case .image, .resource:
                parts.append("[non-text content omitted]")
            }
        }
        return parts.joined(separator: "\n")
    }

    // MARK: - Fingerprint

    nonisolated private static func fingerprint(descriptors: [MCPToolDescriptor]) -> String {
        descriptors
            .map { "\($0.name):\($0.description.hashValue)" }
            .sorted()
            .joined(separator: "|")
    }
}

// MARK: - Errors

public enum MLXAdapterError: Error, LocalizedError {
    /// The tool's arguments were not a JSON object. Shouldn't happen with
    /// MLX's structured tool calls but surfaced explicitly so adapters
    /// can fall back cleanly.
    case invalidArgumentShape(toolName: String)

    public var errorDescription: String? {
        switch self {
        case .invalidArgumentShape(let name):
            return "Tool '\(name)' was called with non-object arguments."
        }
    }
}

// MARK: - Schema → [String: Any]

private func jsonObject<T: Encodable>(_ value: T) -> Any? {
    guard let data = try? JSONEncoder.swiftAgent.encode(value) else { return nil }
    return try? JSONSerialization.jsonObject(with: data)
}

// MARK: - Direct JSONValue converter

extension MLXAdapter {
    /// Recursively translate MLX's `JSONValue` to SwiftAgent's `JSONValue`
    /// without going through `Data`. The two enums have compatible cases
    /// but different number representations (MLX stores all numbers as
    /// `Double`; SwiftAgent preserves integer identity).
    nonisolated fileprivate static func convert(_ value: MLXLMCommon.JSONValue) -> SwiftAgentCore.JSONValue {
        switch value {
        case .null:
            return .null
        case .bool(let b):
            return .bool(b)
        case .int(let i):
            return .int(Int64(i))
        case .double(let d):
            if d.truncatingRemainder(dividingBy: 1) == 0,
               d >= Double(Int64.min),
               d <= Double(Int64.max) {
                return .int(Int64(d))
            }
            return .double(d)
        case .string(let s):
            return .string(s)
        case .array(let items):
            return .array(items.map { convert($0) })
        case .object(let dict):
            var mapped: [String: SwiftAgentCore.JSONValue] = [:]
            mapped.reserveCapacity(dict.count)
            for (key, value) in dict {
                mapped[key] = convert(value)
            }
            return .object(mapped)
        }
    }
}
