import Foundation
import SwiftAgentCore

/// Converts SwiftAgent tool descriptors into Anthropic's `tool_use`
/// format for the Messages API.
///
/// Translates `MCPToolDescriptor` → Anthropic tool JSON, handling
/// the `input_schema` key and content-block response format.
public enum AnthropicToolExport {
    /// Convert a list of tool descriptors into Anthropic `tools` array
    /// suitable for passing to the messages API.
    public static func export(_ descriptors: [MCPToolDescriptor]) -> JSONValue {
        .array(descriptors.map { descriptor in
            .object([
                "name": .string(descriptor.name),
                "description": .string(descriptor.description),
                "input_schema": encodeSchema(descriptor.inputSchema)
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
