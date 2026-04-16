import Foundation

/// Capability bag advertised by a client during `initialize`.
///
/// Today the only well-known client capability is `sampling`, which signals
/// that the client can perform LLM sampling on behalf of the server (used
/// for advanced server→client reverse tool-call flows). Experimental fields
/// are stored verbatim and passed through unmodified.
public struct MCPClientCapabilities: Sendable, Hashable, Codable {
    /// When `true`, the server may request LLM sampling from the client via
    /// the reverse-flow sampling API.
    public var sampling: Bool?

    /// Forward-compatibility bag for experimental capability fields not yet
    /// modeled in this type.
    public var experimental: [String: JSONValue]?

    /// Build a client capability bag.
    ///
    /// - Parameters:
    ///   - sampling: Whether client-side LLM sampling is supported.
    ///   - experimental: Free-form extension fields.
    public init(sampling: Bool? = nil, experimental: [String: JSONValue]? = nil) {
        self.sampling = sampling
        self.experimental = experimental
    }
}
