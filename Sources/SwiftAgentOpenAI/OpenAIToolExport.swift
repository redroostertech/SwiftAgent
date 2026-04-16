import Foundation
import SwiftAgentCore

/// Converts SwiftAgent tool descriptors into OpenAI's `functions` /
/// `tools` JSON format.
///
/// Translates `MCPToolDescriptor` → OpenAI function-calling JSON,
/// handling the schema key differences (`parameters` vs `inputSchema`,
/// `function` wrapper, `strict` mode).
public enum OpenAIToolExport {
    /// Convert a list of tool descriptors into OpenAI `tools` array
    /// suitable for passing to the chat completions API.
    public static func export(_ descriptors: [MCPToolDescriptor]) -> JSONValue {
        .array(descriptors.map { descriptor in
            .object([
                "type": .string("function"),
                "function": .object([
                    "name": .string(descriptor.name),
                    "description": .string(descriptor.description),
                    "parameters": encodeSchema(descriptor.inputSchema)
                ])
            ])
        })
    }

    private static func encodeSchema(_ schema: MCPSchema) -> JSONValue {
        do {
            let data = try JSONEncoder.swiftAgent.encode(schema)
            return try JSONDecoder.swiftAgent.decode(JSONValue.self, from: data)
        } catch {
            return .object([:])
        }
    }
}
