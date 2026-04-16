import Foundation

/// Reference-type indirection for recursive value types.
///
/// A Swift struct cannot contain a stored property of itself (even optional)
/// because its in-memory layout would be unbounded. `Box` wraps the value in
/// a final class so the recursion goes through a reference, while the
/// surface API stays value-like — `Box` is immutable, `Equatable`,
/// `Hashable`, and `Codable`, so clients do not have to reason about it
/// being a class.
///
/// AppMCP uses `Box` inside ``MCPSchema`` to represent `items`, letting one
/// schema describe the element type of another without a layout cycle.
public final class Box<Value: Sendable & Hashable & Codable>: @unchecked Sendable, Hashable, Codable {
    /// The wrapped value. Immutable after construction.
    public let value: Value

    /// Wrap a value in a new box.
    ///
    /// - Parameter value: The value to wrap.
    public init(_ value: Value) {
        self.value = value
    }

    /// Decode a box transparently from a single-value container holding
    /// the wrapped value.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try container.decode(Value.self)
    }

    /// Encode the wrapped value directly into a single-value container, so
    /// the box is invisible on the wire.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    public static func == (lhs: Box<Value>, rhs: Box<Value>) -> Bool {
        lhs.value == rhs.value
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }
}
