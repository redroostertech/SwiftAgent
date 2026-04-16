import XCTest
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
@testable import SwiftAgentMacros

/// Tests that the `@AgentTool` and `@Param` macros produce correct
/// Swift source code via `assertMacroExpansion`.
final class MacroExpansionTests: XCTestCase {
    let macros: [String: any Macro.Type] = [
        "AgentTool": AgentToolMacro.self,
        "Param": ParamMacro.self,
    ]

    func testBasicToolExpansion() {
        assertMacroExpansion(
            """
            @AgentTool("Create a note with a title and body")
            struct CreateNote {
                @Param("Note title") var title: String
                @Param("Markdown body") var body: String

                func perform() async throws -> String {
                    "ok"
                }
            }
            """,
            expandedSource: """
            struct CreateNote {
                var title: String
                var body: String

                func perform() async throws -> String {
                    "ok"
                }
            }

            extension CreateNote: AgentToolProtocol {
                public static var toolName: String {
                    "create_note"
                }
                public static var toolDescription: String {
                    "Create a note with a title and body"
                }

                public static var descriptor: MCPToolDescriptor {
                    var properties: [String: MCPSchema] = [:]
                    var required: [String] = []
                    properties["title"] = MCPSchema.string(description: "Note title")
                    required.append("title")
                    properties["body"] = MCPSchema.string(description: "Markdown body")
                    required.append("body")
                    let inputSchema = MCPSchema.object(
                        properties: properties,
                        required: required,
                        additionalProperties: false
                    )
                    return MCPToolDescriptor(
                        name: toolName,
                        description: toolDescription,
                        inputSchema: inputSchema
                    )
                }

                public static func perform(arguments args: AgentToolArguments) async throws -> MCPCallToolResult {
                    let instance = CreateNote(
                        title: try args.string("title"),
                        body: try args.string("body")
                    )
                    let result = try await instance.perform()
                    return .text(String(describing: result))
                }

                public static func asAgentTool() -> AgentTool {
                    AgentTool(
                        name: toolName,
                        description: toolDescription
                    ) {
                        Parameter.string("title", description: "Note title")
                        Parameter.string("body", description: "Markdown body")
                    } handler: { args in
                        try await perform(arguments: args)
                    }
                }
            }
            """,
            macros: macros
        )
    }

    func testToolWithDefaultParameter() {
        assertMacroExpansion(
            """
            @AgentTool("Pin a note")
            struct PinNote {
                @Param("Note ID") var id: String
                @Param("Pin state") var pinned: Bool = true

                func perform() async throws -> String {
                    "ok"
                }
            }
            """,
            expandedSource: """
            struct PinNote {
                var id: String
                var pinned: Bool = true

                func perform() async throws -> String {
                    "ok"
                }
            }

            extension PinNote: AgentToolProtocol {
                public static var toolName: String {
                    "pin_note"
                }
                public static var toolDescription: String {
                    "Pin a note"
                }

                public static var descriptor: MCPToolDescriptor {
                    var properties: [String: MCPSchema] = [:]
                    var required: [String] = []
                    properties["id"] = MCPSchema.string(description: "Note ID")
                    required.append("id")
                    properties["pinned"] = MCPSchema.boolean(description: "Pin state")
                    let inputSchema = MCPSchema.object(
                        properties: properties,
                        required: required,
                        additionalProperties: false
                    )
                    return MCPToolDescriptor(
                        name: toolName,
                        description: toolDescription,
                        inputSchema: inputSchema
                    )
                }

                public static func perform(arguments args: AgentToolArguments) async throws -> MCPCallToolResult {
                    let instance = PinNote(
                        id: try args.string("id"),
                        pinned: args.optionalBoolean("pinned") ?? true
                    )
                    let result = try await instance.perform()
                    return .text(String(describing: result))
                }

                public static func asAgentTool() -> AgentTool {
                    AgentTool(
                        name: toolName,
                        description: toolDescription
                    ) {
                        Parameter.string("id", description: "Note ID")
                        Parameter.boolean("pinned", description: "Pin state", isRequired: false)
                    } handler: { args in
                        try await perform(arguments: args)
                    }
                }
            }
            """,
            macros: macros
        )
    }

    func testSnakeCaseConversionAndZeroParams() {
        assertMacroExpansion(
            """
            @AgentTool("Fetch")
            struct FetchHTTPRequest {
                func perform() async throws -> String { "ok" }
            }
            """,
            expandedSource: """
            struct FetchHTTPRequest {
                func perform() async throws -> String { "ok" }
            }

            extension FetchHTTPRequest: AgentToolProtocol {
                public static var toolName: String {
                    "fetch_http_request"
                }
                public static var toolDescription: String {
                    "Fetch"
                }

                public static var descriptor: MCPToolDescriptor {
                    var properties: [String: MCPSchema] = [:]
                    var required: [String] = []

                    let inputSchema = MCPSchema.object(
                        properties: properties,
                        required: required,
                        additionalProperties: false
                    )
                    return MCPToolDescriptor(
                        name: toolName,
                        description: toolDescription,
                        inputSchema: inputSchema
                    )
                }

                public static func perform(arguments args: AgentToolArguments) async throws -> MCPCallToolResult {
                    let instance = FetchHTTPRequest()
                    let result = try await instance.perform()
                    return .text(String(describing: result))
                }

                public static func asAgentTool() -> AgentTool {
                    AgentTool(
                        name: toolName,
                        description: toolDescription
                    ) {

                    } handler: { args in
                        try await perform(arguments: args)
                    }
                }
            }
            """,
            macros: macros
        )
    }

    func testParamMacroIsInert() {
        assertMacroExpansion(
            """
            @Param("A description")
            var title: String
            """,
            expandedSource: """
            var title: String
            """,
            macros: macros
        )
    }
}
