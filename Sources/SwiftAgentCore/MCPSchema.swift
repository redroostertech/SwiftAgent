import Foundation

/// A tiny, JSON-Schema-flavored type description used for SwiftAgent tool inputs
/// and outputs.
///
/// SwiftAgent intentionally supports a narrow subset of JSON Schema Draft 7 — the
/// parts LLM tool callers actually use. This keeps wire payloads compact,
/// schemas easy to author by hand, and validation tractable. More exotic
/// features (`allOf`, `oneOf`, `$ref`, custom formats) can be layered on by
/// consumers via the `extra` escape hatch.
public struct MCPSchema: Sendable, Hashable, Codable {
    /// The primitive JSON type this schema matches. Mirrors JSON Schema's
    /// `type` keyword, limited to a single type (no union types).
    public enum SchemaType: String, Sendable, Codable {
        /// A JSON object with named properties.
        case object
        /// A homogeneous JSON array (see ``MCPSchema/items``).
        case array
        /// A JSON string.
        case string
        /// A JSON floating-point number.
        case number
        /// A JSON integer (whole number).
        case integer
        /// A JSON boolean.
        case boolean
        /// The JSON `null` literal.
        case null
    }

    /// The primitive JSON type this schema matches, or `nil` to allow any type.
    public var type: SchemaType?
    /// Human-readable description shown to tool callers (LLMs and humans).
    public var description: String?
    /// Child property schemas, keyed by property name. Only meaningful when
    /// ``type`` is `.object`.
    public var properties: [String: MCPSchema]?
    /// Names of properties that must be present in a valid object.
    public var required: [String]?
    /// Schema applied to every element of an array. Only meaningful when
    /// ``type`` is `.array`.
    public var items: Box<MCPSchema>?
    /// If present, the value must equal one of the listed values. Encoded
    /// as `enum` on the wire.
    public var enumValues: [JSONValue]?
    /// If present, the value must exactly equal this value.
    public var const: JSONValue?
    /// Optional format hint such as `"uri"`, `"email"`, `"date-time"`.
    /// SwiftAgent does not enforce formats — they are a hint to callers.
    public var format: String?
    /// Inclusive lower bound for numeric values.
    public var minimum: Double?
    /// Inclusive upper bound for numeric values.
    public var maximum: Double?
    /// Minimum permitted length of a string (in characters).
    public var minLength: Int?
    /// Maximum permitted length of a string (in characters).
    public var maxLength: Int?
    /// Default value surfaced to UIs and LLM tool callers when the caller
    /// omits this field. SwiftAgent does not auto-populate defaults — they are
    /// advisory.
    public var defaultValue: JSONValue?
    /// When `false`, object values may not contain keys that are not listed
    /// in ``properties``. When `true` or `nil`, additional keys are allowed.
    public var additionalProperties: Bool?
    /// Escape hatch for JSON Schema keywords SwiftAgent does not model
    /// natively. Stored but not round-tripped through the generated
    /// `Codable` conformance.
    public var extra: [String: JSONValue]?

    /// Build a schema by specifying any subset of the supported keywords.
    ///
    /// Most callers will use one of the convenience builders such as
    /// ``object(properties:required:description:additionalProperties:)``
    /// rather than this raw initializer.
    public init(
        type: SchemaType? = nil,
        description: String? = nil,
        properties: [String: MCPSchema]? = nil,
        required: [String]? = nil,
        items: MCPSchema? = nil,
        enumValues: [JSONValue]? = nil,
        const: JSONValue? = nil,
        format: String? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil,
        minLength: Int? = nil,
        maxLength: Int? = nil,
        defaultValue: JSONValue? = nil,
        additionalProperties: Bool? = nil,
        extra: [String: JSONValue]? = nil
    ) {
        self.type = type
        self.description = description
        self.properties = properties
        self.required = required
        self.items = items.map(Box.init)
        self.enumValues = enumValues
        self.const = const
        self.format = format
        self.minimum = minimum
        self.maximum = maximum
        self.minLength = minLength
        self.maxLength = maxLength
        self.defaultValue = defaultValue
        self.additionalProperties = additionalProperties
        self.extra = extra
    }

    private enum CodingKeys: String, CodingKey {
        case type, description, properties, required, items
        case enumValues = "enum"
        case const, format, minimum, maximum, minLength, maxLength
        case defaultValue = "default"
        case additionalProperties
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decodeIfPresent(SchemaType.self, forKey: .type)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.properties = try container.decodeIfPresent([String: MCPSchema].self, forKey: .properties)
        self.required = try container.decodeIfPresent([String].self, forKey: .required)
        self.items = try container.decodeIfPresent(Box<MCPSchema>.self, forKey: .items)
        self.enumValues = try container.decodeIfPresent([JSONValue].self, forKey: .enumValues)
        self.const = try container.decodeIfPresent(JSONValue.self, forKey: .const)
        self.format = try container.decodeIfPresent(String.self, forKey: .format)
        self.minimum = try container.decodeIfPresent(Double.self, forKey: .minimum)
        self.maximum = try container.decodeIfPresent(Double.self, forKey: .maximum)
        self.minLength = try container.decodeIfPresent(Int.self, forKey: .minLength)
        self.maxLength = try container.decodeIfPresent(Int.self, forKey: .maxLength)
        self.defaultValue = try container.decodeIfPresent(JSONValue.self, forKey: .defaultValue)
        self.additionalProperties = try container.decodeIfPresent(Bool.self, forKey: .additionalProperties)
        self.extra = nil
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(properties, forKey: .properties)
        try container.encodeIfPresent(required, forKey: .required)
        try container.encodeIfPresent(items, forKey: .items)
        try container.encodeIfPresent(enumValues, forKey: .enumValues)
        try container.encodeIfPresent(const, forKey: .const)
        try container.encodeIfPresent(format, forKey: .format)
        try container.encodeIfPresent(minimum, forKey: .minimum)
        try container.encodeIfPresent(maximum, forKey: .maximum)
        try container.encodeIfPresent(minLength, forKey: .minLength)
        try container.encodeIfPresent(maxLength, forKey: .maxLength)
        try container.encodeIfPresent(defaultValue, forKey: .defaultValue)
        try container.encodeIfPresent(additionalProperties, forKey: .additionalProperties)
    }
}

// MARK: - Schema builders

extension MCPSchema {
    /// Build an object schema with the given property schemas and required
    /// keys. Defaults `additionalProperties` to `false` so tools get strict
    /// validation out of the box.
    ///
    /// - Parameters:
    ///   - properties: The property name → schema mapping.
    ///   - required: Names of required properties. Empty means no required.
    ///   - description: Optional human-readable description.
    ///   - additionalProperties: Whether unknown keys are permitted.
    ///     Defaults to `false` for strict schemas.
    /// - Returns: An `.object` schema.
    public static func object(
        properties: [String: MCPSchema],
        required: [String] = [],
        description: String? = nil,
        additionalProperties: Bool? = false
    ) -> MCPSchema {
        MCPSchema(
            type: .object,
            description: description,
            properties: properties,
            required: required.isEmpty ? nil : required,
            additionalProperties: additionalProperties
        )
    }

    /// Build an array schema with the given per-element schema.
    ///
    /// - Parameters:
    ///   - item: The schema every element must satisfy.
    ///   - description: Optional human-readable description.
    /// - Returns: An `.array` schema.
    public static func array(of item: MCPSchema, description: String? = nil) -> MCPSchema {
        MCPSchema(type: .array, description: description, items: item)
    }

    /// Build a string schema.
    ///
    /// - Parameters:
    ///   - description: Optional human-readable description.
    ///   - enumValues: Optional closed set of permitted string values.
    ///   - format: Optional JSON Schema `format` hint (advisory only).
    /// - Returns: A `.string` schema.
    public static func string(
        description: String? = nil,
        enumValues: [String]? = nil,
        format: String? = nil
    ) -> MCPSchema {
        MCPSchema(
            type: .string,
            description: description,
            enumValues: enumValues?.map { .string($0) },
            format: format
        )
    }

    /// Build an integer schema with optional numeric bounds.
    public static func integer(description: String? = nil, minimum: Double? = nil, maximum: Double? = nil) -> MCPSchema {
        MCPSchema(type: .integer, description: description, minimum: minimum, maximum: maximum)
    }

    /// Build a floating-point number schema with optional numeric bounds.
    public static func number(description: String? = nil, minimum: Double? = nil, maximum: Double? = nil) -> MCPSchema {
        MCPSchema(type: .number, description: description, minimum: minimum, maximum: maximum)
    }

    /// Build a boolean schema.
    public static func boolean(description: String? = nil) -> MCPSchema {
        MCPSchema(type: .boolean, description: description)
    }
}

// MARK: - Validation

extension MCPSchema {
    /// Validates a JSON value against this schema. Returns a list of errors;
    /// an empty array means the value is valid. Validation is intentionally
    /// permissive — unknown properties are allowed unless
    /// `additionalProperties` is `false`.
    public func validate(_ value: JSONValue, path: String = "$") -> [String] {
        var errors: [String] = []

        if let type {
            let ok: Bool = switch type {
            case .object: value.objectValue != nil
            case .array: value.arrayValue != nil
            case .string: value.stringValue != nil
            case .number: value.doubleValue != nil
            case .integer: value.intValue != nil
            case .boolean: value.boolValue != nil
            case .null: value.isNull
            }
            if !ok {
                errors.append("\(path): expected \(type.rawValue)")
                return errors
            }
        }

        if let enumValues, !enumValues.contains(value) {
            errors.append("\(path): value not in enum")
        }

        if let const, value != const {
            errors.append("\(path): value does not match const")
        }

        switch value {
        case .object(let dict):
            if let required {
                for key in required where dict[key] == nil {
                    errors.append("\(path).\(key): required property missing")
                }
            }
            if let properties {
                for (key, child) in dict {
                    if let childSchema = properties[key] {
                        errors.append(contentsOf: childSchema.validate(child, path: "\(path).\(key)"))
                    } else if additionalProperties == false {
                        errors.append("\(path).\(key): additional property not allowed")
                    }
                }
            }
        case .array(let arr):
            if let items {
                for (index, element) in arr.enumerated() {
                    errors.append(contentsOf: items.value.validate(element, path: "\(path)[\(index)]"))
                }
            }
        case .string(let str):
            if let minLength, str.count < minLength {
                errors.append("\(path): string shorter than minLength \(minLength)")
            }
            if let maxLength, str.count > maxLength {
                errors.append("\(path): string longer than maxLength \(maxLength)")
            }
        case .int(let n):
            if let minimum, Double(n) < minimum {
                errors.append("\(path): value less than minimum \(minimum)")
            }
            if let maximum, Double(n) > maximum {
                errors.append("\(path): value greater than maximum \(maximum)")
            }
        case .double(let n):
            if let minimum, n < minimum {
                errors.append("\(path): value less than minimum \(minimum)")
            }
            if let maximum, n > maximum {
                errors.append("\(path): value greater than maximum \(maximum)")
            }
        default:
            break
        }

        return errors
    }
}

