/// Marks a struct as a SwiftAgent tool.
///
/// The `@AgentTool` macro generates an extension that conforms the
/// struct to `AgentToolProtocol`, synthesizing:
///
/// - `toolName` — the struct name converted to `lower_snake_case`
/// - `toolDescription` — the string you pass to the macro
/// - `descriptor` — an `MCPToolDescriptor` with a JSON Schema derived
///   from the struct's `@Param`-annotated properties
/// - `perform(arguments:)` — dispatches validated arguments to the
///   struct's `perform()` method
/// - `asAgentTool()` — wraps the struct as an ``AgentTool`` for
///   registration with ``AgentServer``
///
/// ### Usage
///
/// ```swift
/// @AgentTool("Create a note with a title and body")
/// struct CreateNote {
///     @Param("Note title") var title: String
///     @Param("Markdown body") var body: String
///     @Param("Pin to top") var pinned: Bool = false
///
///     func perform() async throws -> String {
///         try await NoteStore.shared.create(title: title, body: body, pinned: pinned)
///     }
/// }
///
/// // Register with the server:
/// try await AgentServer.shared.register(CreateNote.asAgentTool())
/// ```
@attached(extension, conformances: AgentToolProtocol, names: named(toolName), named(toolDescription), named(descriptor), named(perform), named(asAgentTool))
public macro AgentTool(_ description: String) = #externalMacro(module: "SwiftAgentMacros", type: "AgentToolMacro")

/// Marks a stored property as a tool parameter with a description.
///
/// The `@Param` attribute is consumed by the `@AgentTool` macro during
/// expansion. It does not generate code on its own — it carries the
/// description string that appears in the tool's JSON Schema and is
/// shown to LLM callers.
///
/// Properties without `@Param` are ignored by `@AgentTool` and will not
/// appear in the tool's parameter list.
@attached(peer)
public macro Param(_ description: String) = #externalMacro(module: "SwiftAgentMacros", type: "ParamMacro")
