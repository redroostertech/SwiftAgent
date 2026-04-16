import Foundation
import SwiftAgentCore
import SwiftAgentServer

#if canImport(AppIntents)
import AppIntents

/// A protocol that an existing `AppIntent` conforms to in order to be
/// exposed through AppMCP as a tool.
///
/// The pitch to consuming apps is simple: **if you already shipped an
/// `AppIntent` to get Siri and Shortcuts integration, one conformance
/// away you also get agentic-MCP integration for free**, with no new
/// permissions, no new sockets, and no background work.
///
/// ### What you declare
///
/// - ``mcpDescription`` — the natural-language description LLM callers
///   see. If you already set `IntentDescription`, you can forward it:
///   `static var mcpDescription: String { Self.description?.stringValue ?? "" }`.
/// - ``mcpParameters`` — the declarative parameter list the framework
///   turns into a JSON Schema and validates arguments against. Use the
///   same ``AgentParameterBuilder`` DSL shipped with the server
///   module, so you can write it inline without learning a second
///   syntax.
/// - ``mcpPerform(_:)`` — how to build your intent's `@Parameter`
///   values from a validated arguments bag, run `perform()`, and map
///   the result into an MCP tool result. You write this once and it is
///   completely mechanical — typically five or six lines.
///
/// ### What you *don't* declare
///
/// You do not re-describe parameter types, re-declare titles, or
/// duplicate any metadata that `AppIntent` already owns. The point of
/// this protocol is that AppMCP sits *alongside* your intent without
/// taking it over.
///
/// ### Example
///
/// ```swift
/// struct CreateNoteIntent: AppIntent {
///     static var title: LocalizedStringResource = "Create Note"
///     static var description = IntentDescription("Creates a new note.")
///
///     @Parameter(title: "Title") var noteTitle: String
///     @Parameter(title: "Body")  var body: String
///
///     func perform() async throws -> some IntentResult & ReturnsValue<String> {
///         let id = try await NoteStore.shared.create(title: noteTitle, body: body)
///         return .result(value: id)
///     }
/// }
///
/// extension CreateNoteIntent: AgentExposableIntent {
///     static var mcpDescription: String { "Create a new note with a title and body." }
///
///     static var mcpParameters: [AppMCPParameter] {
///         [
///             .string("noteTitle", description: "The note's title"),
///             .string("body", description: "Markdown body of the note")
///         ]
///     }
///
///     static func mcpPerform(_ args: AgentToolArguments) async throws -> MCPCallToolResult {
///         var intent = CreateNoteIntent()
///         intent.noteTitle = try args.string("noteTitle")
///         intent.body = try args.string("body")
///         let result = try await intent.perform()
///         if let value = (result as? any ReturnsValue<String>)?.value {
///             return .text(value)
///         }
///         return .text("ok")
///     }
/// }
///
/// // One line at app launch:
/// try await AgentServer.shared.register(intent: CreateNoteIntent.self)
/// ```
@available(iOS 16.0, macOS 13.0, macCatalyst 16.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
public protocol AgentExposableIntent: AppIntent {
    /// Unique MCP tool name. Defaults to the intent type name converted
    /// to snake_case by ``AgentIntentNaming/defaultMCPName(for:)``.
    static var mcpName: String { get }

    /// Optional human-readable display title. Defaults to the intent
    /// title string from `AppIntent.title` when available.
    static var mcpTitle: String? { get }

    /// Natural-language description shown to LLM callers. This is the
    /// one field every adopter must provide — intent descriptions are
    /// written for humans clicking through Shortcuts, and LLMs benefit
    /// from more pointed guidance about when the tool should be used.
    static var mcpDescription: String { get }

    /// Optional behavioral annotations (read-only, destructive, etc.).
    /// Defaults to `nil` — agents will assume the tool may mutate state.
    static var mcpAnnotations: MCPToolAnnotations? { get }

    /// The parameter list used to derive the tool's JSON schema and
    /// validate incoming arguments. Keep the names aligned with your
    /// `@Parameter` property names so ``mcpPerform(_:)`` stays readable.
    static var mcpParameters: [AppMCPParameter] { get }

    /// Build an instance of `Self` from a validated argument bag, run
    /// the intent's `perform()`, and translate the result into an MCP
    /// tool result. The framework invokes this once per `tools/call`.
    ///
    /// - Parameter args: Arguments validated against ``mcpParameters``.
    /// - Returns: The tool-call result to return to the MCP client.
    /// - Throws: ``MCPError`` on argument errors, or any error the
    ///   intent's `perform()` raises.
    static func mcpPerform(_ args: AgentToolArguments) async throws -> MCPCallToolResult
}

// MARK: - Defaults

@available(iOS 16.0, macOS 13.0, macCatalyst 16.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
public extension AgentExposableIntent {
    /// Default name: the type name converted to snake_case.
    /// Override when you want to rename at the AppMCP boundary without
    /// renaming the underlying intent type.
    static var mcpName: String {
        AgentIntentNaming.defaultMCPName(for: Self.self)
    }

    /// Default title: `nil`. Override to provide a localized display
    /// title separate from ``mcpName``.
    static var mcpTitle: String? { nil }

    /// Default annotations: `nil`. Override to mark a tool as
    /// read-only, destructive, idempotent, etc.
    static var mcpAnnotations: MCPToolAnnotations? { nil }
}

#endif
