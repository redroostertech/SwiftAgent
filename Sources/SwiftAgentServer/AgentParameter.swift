import Foundation
import SwiftAgentCore

/// Short alias for ``AppMCPParameter`` so result-builder call sites can
/// read as `Parameter.string("title", …)` without a leading dot.
///
/// Swift's parser treats a line that begins with `.` as a continuation of
/// the previous expression (method chaining), which breaks the natural
/// DSL shape of an ``AgentParameterBuilder`` block with multiple
/// parameters. Declaring the type explicitly — via this alias — avoids
/// the trap and keeps call sites readable. Both forms compile; prefer
/// `Parameter.xxx` in user code.
public typealias Parameter = AppMCPParameter

/// A single parameter of an ``AppMCPTool``.
///
/// `AppMCPParameter` is the declarative building block of the tool DSL.
/// You describe each parameter once — name, type, human-readable
/// description, whether it is required, and an optional default — and the
/// server derives both the JSON-Schema advertised on `tools/list` and the
/// per-argument validation applied at `tools/call` time from this single
/// source of truth.
///
/// Use the factory methods (``string(_:description:isRequired:default:)``,
/// ``integer(_:description:isRequired:default:minimum:maximum:)``, etc.)
/// rather than the raw initializer in almost all cases — they keep the
/// call sites readable and produce a well-formed ``MCPSchema`` for you.
public struct AppMCPParameter: Sendable {
    /// The machine-readable name of the parameter, as it appears in the
    /// JSON arguments object.
    public let name: String

    /// Human-readable description shown to LLM callers and in generated
    /// UIs. Should explain *what the parameter means*, not just restate
    /// its type.
    public let description: String?

    /// The JSON schema describing valid values for this parameter.
    public let schema: MCPSchema

    /// When `true`, the caller must provide this parameter; omitting it
    /// triggers ``MCPError/invalidToolArguments(name:reason:)``.
    public let isRequired: Bool

    /// Optional default value that clients may surface in UI. AppMCP does
    /// not auto-populate defaults at call time — it is up to the caller
    /// to apply them — but the default propagates into the generated
    /// schema so LLMs see the same information.
    public let defaultValue: JSONValue?

    /// Build a parameter from pre-assembled pieces. Prefer the typed
    /// factory methods for readability.
    ///
    /// - Parameters:
    ///   - name: Machine-readable parameter name.
    ///   - description: Human-readable description.
    ///   - schema: JSON schema for valid values.
    ///   - isRequired: Whether the parameter is required.
    ///   - defaultValue: Optional default shown to callers.
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

extension AppMCPParameter {
    /// Declare a string parameter.
    ///
    /// - Parameters:
    ///   - name: Parameter name.
    ///   - description: Human-readable description.
    ///   - isRequired: Whether the parameter is required. Defaults to `true`.
    ///   - defaultValue: Optional default string.
    ///   - enumValues: Optional closed set of permitted values.
    ///   - format: Optional JSON Schema `format` hint (e.g. `"uri"`).
    public static func string(
        _ name: String,
        description: String? = nil,
        isRequired: Bool = true,
        default defaultValue: String? = nil,
        enumValues: [String]? = nil,
        format: String? = nil
    ) -> AppMCPParameter {
        AppMCPParameter(
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
    ) -> AppMCPParameter {
        AppMCPParameter(
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
    ) -> AppMCPParameter {
        AppMCPParameter(
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
    ) -> AppMCPParameter {
        AppMCPParameter(
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
    ) -> AppMCPParameter {
        AppMCPParameter(
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
    ) -> AppMCPParameter {
        AppMCPParameter(
            name: name,
            description: description,
            schema: schema,
            isRequired: isRequired
        )
    }
}
