import Foundation
import SwiftAgentCore

/// Short alias for ``AgentParameter`` so result-builder call sites can
/// read as `Parameter.string("title", …)` without a leading dot.
///
/// Swift's parser treats a line that begins with `.` as a continuation of
/// the previous expression (method chaining), which breaks the natural
/// DSL shape of an ``AgentParameterBuilder`` block with multiple
/// parameters. Declaring the type explicitly — via this alias — avoids
/// the trap and keeps call sites readable.
public typealias Parameter = AgentParameter

/// A single parameter of an ``AgentTool``.
///
/// `AgentParameter` is the declarative building block of the tool DSL.
/// You describe each parameter once — name, type, human-readable
/// description, whether it is required, and an optional default — and the
/// server derives both the JSON-Schema advertised on `tools/list` and the
/// per-argument validation applied at `tools/call` time from this single
/// source of truth.
///
/// Use the factory methods (``string(_:description:isRequired:default:)``,
/// ``integer(_:description:isRequired:default:minimum:maximum:)``, etc.)
/// rather than the raw initializer in almost all cases.
public struct AgentParameter: Sendable {
    /// The machine-readable name of the parameter.
    public let name: String

    /// Human-readable description shown to LLM callers and generated UIs.
    public let description: String?

    /// The JSON schema describing valid values for this parameter.
    public let schema: MCPSchema

    /// When `true`, the caller must provide this parameter.
    public let isRequired: Bool

    /// Optional default value that clients may surface in UI. SwiftAgent does
    /// not auto-populate defaults at call time — they are advisory.
    public let defaultValue: JSONValue?

    /// Build a parameter from pre-assembled pieces.
    public init(
        name: String,
        description: String? = nil,
        schema: MCPSchema,
        isRequired: Bool = true,
        defaultValue: JSONValue? = nil
    ) {
        self.name = name
        self.description = description
        var schemaWithDescription = schema
        if schemaWithDescription.description == nil {
            schemaWithDescription.description = description
        }
        if schemaWithDescription.defaultValue == nil {
            schemaWithDescription.defaultValue = defaultValue
        }
        self.schema = schemaWithDescription
        self.isRequired = isRequired
        self.defaultValue = defaultValue
    }
}

// MARK: - Typed factories

extension AgentParameter {
    /// Declare a string parameter.
    public static func string(
        _ name: String,
        description: String? = nil,
        isRequired: Bool = true,
        default defaultValue: String? = nil,
        enumValues: [String]? = nil,
        format: String? = nil
    ) -> AgentParameter {
        AgentParameter(
            name: name,
            description: description,
            schema: .string(description: description, enumValues: enumValues, format: format),
            isRequired: isRequired,
            defaultValue: defaultValue.map(JSONValue.string)
        )
    }

    /// Declare an integer parameter with optional numeric bounds.
    public static func integer(
        _ name: String,
        description: String? = nil,
        isRequired: Bool = true,
        default defaultValue: Int64? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil
    ) -> AgentParameter {
        AgentParameter(
            name: name,
            description: description,
            schema: .integer(description: description, minimum: minimum, maximum: maximum),
            isRequired: isRequired,
            defaultValue: defaultValue.map(JSONValue.int)
        )
    }

    /// Declare a floating-point number parameter with optional numeric bounds.
    public static func number(
        _ name: String,
        description: String? = nil,
        isRequired: Bool = true,
        default defaultValue: Double? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil
    ) -> AgentParameter {
        AgentParameter(
            name: name,
            description: description,
            schema: .number(description: description, minimum: minimum, maximum: maximum),
            isRequired: isRequired,
            defaultValue: defaultValue.map(JSONValue.double)
        )
    }

    /// Declare a boolean parameter.
    public static func boolean(
        _ name: String,
        description: String? = nil,
        isRequired: Bool = true,
        default defaultValue: Bool? = nil
    ) -> AgentParameter {
        AgentParameter(
            name: name,
            description: description,
            schema: .boolean(description: description),
            isRequired: isRequired,
            defaultValue: defaultValue.map(JSONValue.bool)
        )
    }

    /// Declare an array parameter whose elements conform to `itemSchema`.
    public static func array(
        _ name: String,
        of itemSchema: MCPSchema,
        description: String? = nil,
        isRequired: Bool = true
    ) -> AgentParameter {
        AgentParameter(
            name: name,
            description: description,
            schema: .array(of: itemSchema, description: description),
            isRequired: isRequired
        )
    }

    /// Declare an object parameter with a nested schema.
    public static func object(
        _ name: String,
        description: String? = nil,
        isRequired: Bool = true,
        schema: MCPSchema
    ) -> AgentParameter {
        AgentParameter(
            name: name,
            description: description,
            schema: schema,
            isRequired: isRequired
        )
    }
}
