import Foundation

/// A type-erased JSON value used across the SwiftAgent wire protocol.
///
/// `JSONValue` is the canonical representation of any JSON payload that
/// crosses the SwiftAgent boundary — tool arguments, tool results, JSON-RPC
/// request/response params, schema literals, and error `data` blobs all flow
/// through this type.
///
/// Design choices worth knowing about:
///
/// - **Integer vs. double are distinct cases.** JSON technically has only
///   "number", but preserving integer identity avoids lossy round-trips for
///   IDs, timestamps, and counters that Swift and LLMs both care about.
/// - **`Sendable` so values cross actor boundaries freely.** Every associated
///   value is itself `Sendable`.
/// - **`Hashable` so values can be used as dictionary keys** or compared in
///   tests, schema `enum`, and `const` validation.
/// - **Codable conformance is hand-written** so decoding tries the narrowest
///   type first (bool → int → double → string → array → object), producing
///   the most specific case possible.
public enum JSONValue: Sendable, Hashable {
    /// JSON `null`.
    case null
    /// A JSON boolean.
    case bool(Bool)
    /// A JSON integer. Stored as `Int64` to safely represent values up to
    /// 2⁶³−1 (timestamps, large identifiers, etc.).
    case int(Int64)
    /// A JSON floating-point number.
    case double(Double)
    /// A JSON string.
    case string(String)
    /// A JSON array of further `JSONValue`s.
    case array([JSONValue])
    /// A JSON object. Keys are strings, values are further `JSONValue`s.
    case object([String: JSONValue])
}

// MARK: - Codable

extension JSONValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int64.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Value is not a valid JSON primitive, array, or object."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

// MARK: - ExpressibleBy literals

extension JSONValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) { self = .null }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int64) { self = .int(value) }
}

extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .double(value) }
}

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}

// MARK: - Convenience accessors

extension JSONValue {
    /// `true` if this value is the `null` case.
    public var isNull: Bool { if case .null = self { true } else { false } }

    /// The wrapped `Bool`, or `nil` if this value is any other case.
    public var boolValue: Bool? { if case .bool(let v) = self { v } else { nil } }

    /// The wrapped integer, bridging losslessly from a `.double` case when the
    /// stored double has no fractional component and fits in `Int64`.
    /// Returns `nil` for non-numeric values.
    public var intValue: Int64? {
        switch self {
        case .int(let v): v
        case .double(let v) where v.rounded() == v && v >= Double(Int64.min) && v <= Double(Int64.max): Int64(v)
        default: nil
        }
    }

    /// The wrapped floating-point value, promoting an `.int` case to `Double`
    /// when present. Returns `nil` for non-numeric values.
    public var doubleValue: Double? {
        switch self {
        case .double(let v): v
        case .int(let v): Double(v)
        default: nil
        }
    }

    /// The wrapped `String`, or `nil` if this value is any other case.
    public var stringValue: String? { if case .string(let v) = self { v } else { nil } }

    /// The wrapped array, or `nil` if this value is not an array.
    public var arrayValue: [JSONValue]? { if case .array(let v) = self { v } else { nil } }

    /// The wrapped object dictionary, or `nil` if this value is not an object.
    public var objectValue: [String: JSONValue]? { if case .object(let v) = self { v } else { nil } }

    /// Look up a value by key when `self` is an object.
    ///
    /// - Parameter key: The object key to look up.
    /// - Returns: The child value, or `nil` if the key is missing or `self`
    ///   is not an object.
    public subscript(key: String) -> JSONValue? {
        if case .object(let dict) = self { dict[key] } else { nil }
    }

    /// Look up a value by index when `self` is an array.
    ///
    /// - Parameter index: The array position to access.
    /// - Returns: The element, or `nil` if `self` is not an array or the
    ///   index is out of bounds.
    public subscript(index: Int) -> JSONValue? {
        if case .array(let arr) = self, arr.indices.contains(index) { arr[index] } else { nil }
    }
}

// MARK: - Bridging from Swift primitives

extension JSONValue {
    /// Best-effort construction from an arbitrary `Any`, such as the untyped
    /// output of `JSONSerialization.jsonObject(with:)` or a dictionary
    /// produced by Objective-C interop.
    ///
    /// Recognized inputs: `NSNull`, `Bool`, `Int`, `Int64`, `Double`, `String`,
    /// `[Any]`, and `[String: Any]`. Nested arrays and objects are walked
    /// recursively; the first element that cannot be represented as JSON
    /// causes the entire construction to fail.
    ///
    /// - Parameter value: The untyped value to convert.
    /// - Returns: A `JSONValue` on success, `nil` if `value` is not
    ///   representable.
    public init?(any value: Any) {
        switch value {
        case is NSNull:
            self = .null
        case let bool as Bool:
            self = .bool(bool)
        case let int as Int:
            self = .int(Int64(int))
        case let int as Int64:
            self = .int(int)
        case let double as Double:
            self = .double(double)
        case let string as String:
            self = .string(string)
        case let array as [Any]:
            var out: [JSONValue] = []
            out.reserveCapacity(array.count)
            for element in array {
                guard let converted = JSONValue(any: element) else { return nil }
                out.append(converted)
            }
            self = .array(out)
        case let object as [String: Any]:
            var out: [String: JSONValue] = [:]
            out.reserveCapacity(object.count)
            for (key, element) in object {
                guard let converted = JSONValue(any: element) else { return nil }
                out[key] = converted
            }
            self = .object(out)
        default:
            return nil
        }
    }
}
