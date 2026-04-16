import Foundation

/// Identifier for a JSON-RPC 2.0 request.
///
/// The JSON-RPC spec allows ids to be either a string or a number. SwiftAgent
/// only emits integer ids from its own client, but will accept either when
/// servicing requests from other implementations. A nil id denotes a
/// notification — see ``JSONRPCRequest/isNotification``.
public enum JSONRPCID: Sendable, Hashable, Codable {
    /// A string-typed request id.
    case string(String)
    /// An integer-typed request id. Stored as `Int64` for headroom.
    case int(Int64)

    /// Decode a JSON-RPC id, accepting either a JSON number or string.
    ///
    /// - Parameter decoder: The decoder positioned at the id value.
    /// - Throws: `DecodingError` if the value is neither a number nor string.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int64.self) {
            self = .int(int)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "JSON-RPC id must be a string or integer."
            )
        }
    }

    /// Encode this id into its JSON-RPC wire representation.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        }
    }
}
