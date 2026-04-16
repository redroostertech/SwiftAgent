import Foundation

/// The protocol that the `@AgentTool` macro generates conformance to.
///
/// Every tool in the SwiftAgent system — whether authored via the macro,
/// manually constructed as an ``AgentTool``, or bridged from an
/// ``AgentExposableIntent`` — ultimately produces an
/// ``MCPToolDescriptor`` and a callable `perform()` method. This
/// protocol unifies that contract so adapters (OpenAI, Anthropic,
/// Foundation Models, MCP wire) can consume any tool without caring how
/// it was declared.
///
/// Most developers will never write this conformance by hand — the
/// `@AgentTool` macro generates it. The protocol exists so the library's
/// internal plumbing has a single type to key off of.
public protocol AgentToolProtocol: Sendable {
    /// The tool's machine-readable name. Convention: `lower_snake_case`.
    static var toolName: String { get }

    /// Natural-language description shown to LLM callers and UIs.
    static var toolDescription: String { get }

    /// The wire-format descriptor derived from this tool's declaration.
    /// Contains the JSON Schema for arguments, behavioral annotations,
    /// and optional output schema.
    static var descriptor: MCPToolDescriptor { get }

    /// Execute the tool with the supplied arguments and return a result.
    ///
    /// - Parameter arguments: Validated arguments matching the tool's
    ///   declared input schema.
    /// - Returns: The tool's result, ready for wire serialization.
    /// - Throws: ``MCPError`` or any application error. Thrown errors
    ///   are translated into JSON-RPC error responses by the transport.
    static func perform(arguments: AgentToolArguments) async throws -> MCPCallToolResult
}

/// Typed accessor for tool arguments. Re-exported here so the protocol
/// and its argument type live in the same module. The full implementation
/// is in `SwiftAgentServer`.
///
/// When the protocol is used from `SwiftAgentCore` alone (without the
/// server module), this forward-declares the type the macro will
/// reference.
public struct AgentToolArguments: Sendable {
    /// The raw JSON arguments blob.
    public let raw: JSONValue?

    /// The name of the tool these arguments belong to.
    public let toolName: String

    /// Build an argument accessor.
    public init(raw: JSONValue?, toolName: String) {
        self.raw = raw
        self.toolName = toolName
    }

    /// Look up a raw value by key.
    public subscript(_ key: String) -> JSONValue? {
        raw?[key]
    }

    /// Read a required string argument.
    public func string(_ name: String) throws -> String {
        guard let value = self[name]?.stringValue else {
            throw MCPError.invalidToolArguments(name: toolName, reason: "missing or non-string argument '\(name)'")
        }
        return value
    }

    /// Read an optional string argument.
    public func optionalString(_ name: String) -> String? {
        self[name]?.stringValue
    }

    /// Read a required integer argument.
    public func integer(_ name: String) throws -> Int64 {
        guard let value = self[name]?.intValue else {
            throw MCPError.invalidToolArguments(name: toolName, reason: "missing or non-integer argument '\(name)'")
        }
        return value
    }

    /// Read an optional integer argument.
    public func optionalInteger(_ name: String) -> Int64? {
        self[name]?.intValue
    }

    /// Read a required number argument.
    public func number(_ name: String) throws -> Double {
        guard let value = self[name]?.doubleValue else {
            throw MCPError.invalidToolArguments(name: toolName, reason: "missing or non-number argument '\(name)'")
        }
        return value
    }

    /// Read an optional number argument.
    public func optionalNumber(_ name: String) -> Double? {
        self[name]?.doubleValue
    }

    /// Read a required boolean argument.
    public func boolean(_ name: String) throws -> Bool {
        guard let value = self[name]?.boolValue else {
            throw MCPError.invalidToolArguments(name: toolName, reason: "missing or non-boolean argument '\(name)'")
        }
        return value
    }

    /// Read an optional boolean argument.
    public func optionalBoolean(_ name: String) -> Bool? {
        self[name]?.boolValue
    }

    /// Read a required array argument.
    public func array(_ name: String) throws -> [JSONValue] {
        guard let value = self[name]?.arrayValue else {
            throw MCPError.invalidToolArguments(name: toolName, reason: "missing or non-array argument '\(name)'")
        }
        return value
    }

    /// Read a required object argument.
    public func object(_ name: String) throws -> [String: JSONValue] {
        guard let value = self[name]?.objectValue else {
            throw MCPError.invalidToolArguments(name: toolName, reason: "missing or non-object argument '\(name)'")
        }
        return value
    }
}
