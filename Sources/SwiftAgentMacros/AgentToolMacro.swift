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

        let initArgs = buildMemberwiseInit(params)

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
                let instance = \(raw: structName)(\(raw: initArgs))
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


    private static func buildParameterDeclarations(_ params: [ParamInfo]) -> String {
        var lines: [String] = []
        for param in params {
            let desc = param.description.map { "description: \"\(escapeStringLiteral($0))\"" } ?? ""
            let schemaCall = schemaTypeWithDescription(for: param.type, description: desc)
            lines.append("properties[\"\(param.name)\"] = \(schemaCall)")
            if !param.hasDefault {
                lines.append("required.append(\"\(param.name)\")")
            }
        }
        return lines.joined(separator: "\n        ")
    }

    private static func schemaTypeWithDescription(for swiftType: String, description: String) -> String {
        let descArg = description.isEmpty ? "" : description
        switch swiftType {
        case "String":
            return descArg.isEmpty ? "MCPSchema.string()" : "MCPSchema.string(\(descArg))"
        case "Int", "Int64", "Int32", "Int16", "Int8":
            return descArg.isEmpty ? "MCPSchema.integer()" : "MCPSchema.integer(\(descArg))"
        case "Double", "Float":
            return descArg.isEmpty ? "MCPSchema.number()" : "MCPSchema.number(\(descArg))"
        case "Bool":
            return descArg.isEmpty ? "MCPSchema.boolean()" : "MCPSchema.boolean(\(descArg))"
        default:
            return descArg.isEmpty ? "MCPSchema.string()" : "MCPSchema.string(\(descArg))"
        }
    }

    /// Generates a memberwise initializer call that pulls each parameter
    /// from the arguments bag. Required params use throwing accessors;
    /// optional params use optional accessors with the declared default
    /// as the fallback.
    private static func buildMemberwiseInit(_ params: [ParamInfo]) -> String {
        guard !params.isEmpty else { return "" }
        var args: [String] = []
        for param in params {
            if param.hasDefault {
                let fallback = param.defaultExpr ?? defaultForType(param.type)
                args.append("\(param.name): \(optionalAccessor(for: param))?? \(fallback)")
            } else {
                args.append("\(param.name): \(requiredAccessor(for: param))")
            }
        }
        if args.count == 1 {
            return args[0]
        }
        return "\n            " + args.joined(separator: ",\n            ") + "\n        "
    }

    private static let integerTypes = ["Int", "Int64", "Int32", "Int16", "Int8"]
    private static let floatTypes = ["Double", "Float"]

    private static func requiredAccessor(for param: ParamInfo) -> String {
        if param.type == "String" {
            return "try args.string(\"\(param.name)\")"
        } else if integerTypes.contains(param.type) {
            return "\(param.type)(try args.integer(\"\(param.name)\"))"
        } else if floatTypes.contains(param.type) {
            return "\(param.type)(try args.number(\"\(param.name)\"))"
        } else if param.type == "Bool" {
            return "try args.boolean(\"\(param.name)\")"
        } else {
            return "try args.string(\"\(param.name)\")"
        }
    }

    private static func optionalAccessor(for param: ParamInfo) -> String {
        if param.type == "String" {
            return "args.optionalString(\"\(param.name)\") "
        } else if integerTypes.contains(param.type) {
            let cast = param.type == "Int64" ? "" : ".map(\(param.type).init) "
            return "args.optionalInteger(\"\(param.name)\")\(cast) "
        } else if floatTypes.contains(param.type) {
            let cast = param.type == "Double" ? "" : ".map(\(param.type).init) "
            return "args.optionalNumber(\"\(param.name)\")\(cast) "
        } else if param.type == "Bool" {
            return "args.optionalBoolean(\"\(param.name)\") "
        } else {
            return "args.optionalString(\"\(param.name)\") "
        }
    }

    private static func defaultForType(_ type: String) -> String {
        switch type {
        case "String": return "\"\""
        case "Bool": return "false"
        case "Double", "Float": return "0.0"
        default: return "0"
        }
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
