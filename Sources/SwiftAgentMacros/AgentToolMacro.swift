import SwiftSyntax
import SwiftSyntaxMacros

/// The `@AgentTool` macro implementation.
///
/// Generates an extension on the annotated struct that conforms it to
/// `AgentToolProtocol`, providing:
/// - `toolName` — derived from the struct name via snake_case
/// - `toolDescription` — the string literal passed to `@AgentTool("...")`
/// - `descriptor` — an `MCPToolDescriptor` built from `@Param` properties
/// - `perform(arguments:)` — dispatches to the struct's `perform()` method
/// - `asAgentTool()` — factory that wraps the struct as an `AgentTool`
public struct AgentToolMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw MacroError("@AgentTool can only be applied to structs")
        }

        let structName = structDecl.name.trimmedDescription
        let toolName = snakeCase(structName)
        let description = extractDescription(from: node) ?? structName

        let params = extractParams(from: structDecl)
        let parameterDecls = buildParameterDeclarations(params)
        let performArgs = buildPerformArguments(params, structName: structName)

        let ext: DeclSyntax = """
        extension \(raw: structName): AgentToolProtocol {
            public static var toolName: String { "\(raw: toolName)" }
            public static var toolDescription: String { "\(raw: escapeStringLiteral(description))" }

            public static var descriptor: MCPToolDescriptor {
                var properties: [String: MCPSchema] = [:]
                var required: [String] = []
                \(raw: parameterDecls)
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
                var instance = \(raw: structName)()
                \(raw: performArgs)
                let result = try await instance.perform()
                return .text(String(describing: result))
            }

            public static func asAgentTool() -> AgentTool {
                AgentTool(
                    name: toolName,
                    description: toolDescription
                ) {
                    \(raw: buildParameterBuilderEntries(params))
                } handler: { args in
                    try await perform(arguments: args)
                }
            }
        }
        """

        guard let extensionDecl = ext.as(ExtensionDeclSyntax.self) else {
            return []
        }
        return [extensionDecl]
    }

    // MARK: - Extraction helpers

    private static func extractDescription(from node: AttributeSyntax) -> String? {
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self),
              let first = arguments.first,
              let literal = first.expression.as(StringLiteralExprSyntax.self) else {
            return nil
        }
        return literal.segments.description
    }

    private struct ParamInfo {
        let name: String
        let type: String
        let description: String?
        let hasDefault: Bool
        let defaultExpr: String?
    }

    private static func extractParams(from structDecl: StructDeclSyntax) -> [ParamInfo] {
        var params: [ParamInfo] = []
        for member in structDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                  let binding = varDecl.bindings.first,
                  let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                  let typeAnnotation = binding.typeAnnotation else {
                continue
            }

            let hasParamAttr = varDecl.attributes.contains { attr in
                if let identAttr = attr.as(AttributeSyntax.self),
                   let identType = identAttr.attributeName.as(IdentifierTypeSyntax.self) {
                    return identType.name.trimmedDescription == "Param"
                }
                return false
            }

            guard hasParamAttr else { continue }

            let name = pattern.identifier.trimmedDescription
            let type = typeAnnotation.type.trimmedDescription
            let description = extractParamDescription(from: varDecl)
            let hasDefault = binding.initializer != nil
            let defaultExpr = binding.initializer?.value.trimmedDescription

            params.append(ParamInfo(
                name: name,
                type: type,
                description: description,
                hasDefault: hasDefault,
                defaultExpr: defaultExpr
            ))
        }
        return params
    }

    private static func extractParamDescription(from varDecl: VariableDeclSyntax) -> String? {
        for attr in varDecl.attributes {
            guard let attrSyntax = attr.as(AttributeSyntax.self),
                  let identType = attrSyntax.attributeName.as(IdentifierTypeSyntax.self),
                  identType.name.trimmedDescription == "Param",
                  let args = attrSyntax.arguments?.as(LabeledExprListSyntax.self),
                  let first = args.first,
                  let literal = first.expression.as(StringLiteralExprSyntax.self) else {
                continue
            }
            return literal.segments.description
        }
        return nil
    }

    // MARK: - Code generation helpers

    private static func schemaType(for swiftType: String) -> String {
        switch swiftType {
        case "String": return ".string()"
        case "Int", "Int64", "Int32", "Int16", "Int8": return ".integer()"
        case "Double", "Float": return ".number()"
        case "Bool": return ".boolean()"
        default: return ".string()"
        }
    }

    private static func argAccessor(for swiftType: String) -> String {
        switch swiftType {
        case "String": return "string"
        case "Int", "Int64", "Int32", "Int16", "Int8": return "integer"
        case "Double", "Float": return "number"
        case "Bool": return "boolean"
        default: return "string"
        }
    }

    private static func buildParameterDeclarations(_ params: [ParamInfo]) -> String {
        var lines: [String] = []
        for param in params {
            let desc = param.description.map { ", description: \"\(escapeStringLiteral($0))\"" } ?? ""
            lines.append("properties[\"\(param.name)\"] = MCPSchema\(schemaType(for: param.type))")
            if !param.hasDefault {
                lines.append("required.append(\"\(param.name)\")")
            }
            _ = desc
        }
        return lines.joined(separator: "\n        ")
    }

    private static func buildPerformArguments(_ params: [ParamInfo], structName: String) -> String {
        var lines: [String] = []
        for param in params {
            let accessor = argAccessor(for: param.type)
            if param.hasDefault {
                let castSuffix = param.type == "Int" ? "Int64" : param.type
                if param.type == "Bool" {
                    lines.append("if let val = args.optionalBoolean(\"\(param.name)\") { instance.\(param.name) = val }")
                } else if param.type == "String" {
                    lines.append("if let val = args.optionalString(\"\(param.name)\") { instance.\(param.name) = val }")
                } else if ["Int", "Int64"].contains(param.type) {
                    lines.append("if let val = args.optionalInteger(\"\(param.name)\") { instance.\(param.name) = \(param.type)(val) }")
                } else if ["Double", "Float"].contains(param.type) {
                    lines.append("if let val = args.optionalNumber(\"\(param.name)\") { instance.\(param.name) = \(param.type)(val) }")
                } else {
                    lines.append("if let val = args.optionalString(\"\(param.name)\") { instance.\(param.name) = val }")
                }
            } else {
                if param.type == "String" {
                    lines.append("instance.\(param.name) = try args.string(\"\(param.name)\")")
                } else if ["Int", "Int64"].contains(param.type) {
                    lines.append("instance.\(param.name) = \(param.type)(try args.integer(\"\(param.name)\"))")
                } else if ["Double", "Float"].contains(param.type) {
                    lines.append("instance.\(param.name) = \(param.type)(try args.number(\"\(param.name)\"))")
                } else if param.type == "Bool" {
                    lines.append("instance.\(param.name) = try args.boolean(\"\(param.name)\")")
                } else {
                    lines.append("instance.\(param.name) = try args.string(\"\(param.name)\")")
                }
            }
        }
        return lines.joined(separator: "\n        ")
    }

    private static func buildParameterBuilderEntries(_ params: [ParamInfo]) -> String {
        var lines: [String] = []
        for param in params {
            let schemaMethod: String
            switch param.type {
            case "String": schemaMethod = "string"
            case "Int", "Int64", "Int32": schemaMethod = "integer"
            case "Double", "Float": schemaMethod = "number"
            case "Bool": schemaMethod = "boolean"
            default: schemaMethod = "string"
            }
            let desc = param.description.map { ", description: \"\(escapeStringLiteral($0))\"" } ?? ""
            let req = param.hasDefault ? ", isRequired: false" : ""
            lines.append("Parameter.\(schemaMethod)(\"\(param.name)\"\(desc)\(req))")
        }
        return lines.joined(separator: "\n            ")
    }

    // MARK: - Utilities

    private static func snakeCase(_ name: String) -> String {
        guard !name.isEmpty else { return name }
        var output: [Character] = []
        let characters = Array(name)
        for index in characters.indices {
            let current = characters[index]
            if current.isUppercase {
                let previousIsLower = index > 0 && characters[index - 1].isLowercase
                let previousIsUpper = index > 0 && characters[index - 1].isUppercase
                let nextIsLower = (index + 1 < characters.count) && characters[index + 1].isLowercase
                if (previousIsLower || (previousIsUpper && nextIsLower)) && !output.isEmpty {
                    output.append("_")
                }
                output.append(Character(current.lowercased()))
            } else {
                output.append(current)
            }
        }
        return String(output)
    }

    private static func escapeStringLiteral(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: "\\n")
    }
}

/// Error type for macro diagnostics.
struct MacroError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { self.description = message }
}
