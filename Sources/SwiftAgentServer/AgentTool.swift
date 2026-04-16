import Foundation
import SwiftAgentCore

/// A runnable tool registered with an ``AgentServer``.
///
/// `AgentTool` is the declarative façade over the MCP tool surface.
/// Developers describe a tool once — its name, what it does, what
/// arguments it accepts, and how to run it — and the framework:
///
/// 1. Derives a ``MCPToolDescriptor`` (the wire metadata surfaced on
///    `tools/list`) from the declaration.
/// 2. Validates incoming `tools/call` arguments against the declared
///    parameter schema before invoking the handler.
/// 3. Hosts the handler behind the server actor, serializing concurrent
///    calls correctly.
/// 4. Translates thrown errors into well-formed JSON-RPC errors.
///
/// Consuming apps pay **zero** cost beyond writing the declaration. No
/// new permissions, no new entitlements, no background work, no sockets.
/// When nothing is connected, a registered tool is inert.
///
/// ### Example
///
/// ```swift
/// let createNote = AgentTool(
///     name: "create_note",
///     title: "Create Note",
///     description: "Create a new note with a title and body.",
///     annotations: .init(readOnly: false, destructive: false, idempotent: false)
/// ) {
///     Parameter.string("title", description: "The note's title")
///     Parameter.string("body", description: "Markdown body of the note")
///     Parameter.boolean("pinned", description: "Pin to top of list",
///                       isRequired: false, default: false)
/// } handler: { args in
///     let title = try args.string("title")
///     let body = try args.string("body")
///     let pinned = args.optionalBoolean("pinned") ?? false
///     let id = try await NoteStore.shared.create(
///         title: title, body: body, pinned: pinned
///     )
///     return .text(id)
/// }
///
/// try await AgentServer.shared.register(createNote)
/// ```
///
/// > Important: Use `Parameter.xxx(...)` with the explicit type name
/// > rather than `.xxx(...)`. Swift's parser treats a line that begins
/// > with `.` as a continuation of the previous expression, which
/// > breaks a multi-parameter result-builder block.
public struct AgentTool: Sendable {
    /// The handler signature run when a `tools/call` arrives. Handlers are
    /// `async throws` so they can do real work (I/O, Core Data, etc.) and
    /// surface typed errors that become JSON-RPC errors automatically.
    public typealias Handler = @Sendable (AgentToolArguments) async throws -> MCPCallToolResult

    /// Machine-readable tool name. Must be unique within a server.
    public let name: String

    /// Optional human-readable title. Falls back to ``name``.
    public let title: String?

    /// Natural-language description shown to LLM callers and UIs.
    public let description: String

    /// Parameter declarations in the order they should be rendered.
    public let parameters: [AgentParameter]

    /// Optional behavioral annotations (read-only, destructive, etc.).
    public let annotations: MCPToolAnnotations?

    /// Optional schema describing the tool's structured return value.
    public let outputSchema: MCPSchema?

    /// The handler executed when this tool is called.
    public let handler: Handler

    /// Build a tool using the declarative parameter builder.
    ///
    /// - Parameters:
    ///   - name: Unique machine-readable tool name.
    ///   - title: Optional human-readable display title.
    ///   - description: Natural-language description for callers.
    ///   - annotations: Optional behavioral annotations.
    ///   - outputSchema: Optional schema for the structured return value.
    ///   - parameters: Parameter list built via ``AgentParameterBuilder``.
    ///   - handler: The async handler to run on `tools/call`.
    public init(
        name: String,
        title: String? = nil,
        description: String,
        annotations: MCPToolAnnotations? = nil,
        outputSchema: MCPSchema? = nil,
        @AgentParameterBuilder parameters: () -> [AgentParameter] = { [] },
        handler: @escaping Handler
    ) {
        self.name = name
        self.title = title
        self.description = description
        self.parameters = parameters()
        self.annotations = annotations
        self.outputSchema = outputSchema
        self.handler = handler
    }

    /// The wire-format descriptor advertised on `tools/list`.
    ///
    /// Derived lazily from the parameter declarations so the server never
    /// has to hand-write JSON Schema. Required parameters are collected
    /// into the schema's `required` array in declaration order.
    public var descriptor: MCPToolDescriptor {
        var properties: [String: MCPSchema] = [:]
        var required: [String] = []
        for parameter in parameters {
            properties[parameter.name] = parameter.schema
            if parameter.isRequired { required.append(parameter.name) }
        }
        let inputSchema = MCPSchema.object(
            properties: properties,
            required: required,
            description: description,
            additionalProperties: false
        )
        return MCPToolDescriptor(
            name: name,
            title: title,
            description: description,
            inputSchema: inputSchema,
            outputSchema: outputSchema,
            annotations: annotations
        )
    }

    /// Internal: lookup table for argument validation.
    internal var parametersByName: [String: AgentParameter] {
        Dictionary(uniqueKeysWithValues: parameters.map { ($0.name, $0) })
    }
}
