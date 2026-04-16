import Foundation

/// A tool advertised by an AppMCP server to its clients.
///
/// A descriptor is pure metadata: it names the tool, describes its purpose
/// in natural language, and declares the JSON shape of its inputs (and
/// optionally outputs). Server-side runtime code lives separately — see
/// ``AppMCPTool`` in the `AgentServer` module for the executable form.
public struct MCPToolDescriptor: Sendable, Hashable, Codable {
    /// The tool's machine-readable name. Must be unique within a server.
    /// Convention: lower snake case (`create_note`, `search_messages`).
    public var name: String

    /// An optional human-readable display title. If `nil`, UIs should fall
    /// back to ``name`` with underscores converted to spaces.
    public var title: String?

    /// Natural-language description shown to LLM callers and human users.
    /// Should be specific enough that a caller knows when *and when not*
    /// to invoke the tool.
    public var description: String

    /// Schema describing valid arguments. Always an object schema in
    /// practice, with one property per declared parameter.
    public var inputSchema: MCPSchema

    /// Optional schema describing the structured output field of the
    /// result, when the tool returns machine-readable data alongside any
    /// human-readable content.
    public var outputSchema: MCPSchema?

    /// Optional behavioral hints used by agents when deciding whether to
    /// auto-approve a call.
    public var annotations: MCPToolAnnotations?

    /// Build a tool descriptor.
    ///
    /// - Parameters:
    ///   - name: Unique machine name.
    ///   - title: Optional human-readable title.
    ///   - description: Natural-language description.
    ///   - inputSchema: Argument schema (typically an object schema).
    ///   - outputSchema: Optional structured-output schema.
    ///   - annotations: Optional behavioral annotations.
    public init(
        name: String,
        title: String? = nil,
        description: String,
        inputSchema: MCPSchema,
        outputSchema: MCPSchema? = nil,
        annotations: MCPToolAnnotations? = nil
    ) {
        self.name = name
        self.title = title
        self.description = description
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.annotations = annotations
    }
}
