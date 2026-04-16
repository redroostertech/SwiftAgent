import Foundation

/// A framed JSON-RPC 2.0 message — either a request (call or notification)
/// or a response.
///
/// Transport implementations use this type as the unit passed between the
/// framing/decoding layer and the dispatching layer.
public enum JSONRPCMessage: Sendable {
    /// An incoming or outgoing request message.
    case request(JSONRPCRequest)
    /// An incoming or outgoing response message.
    case response(JSONRPCResponse)
}
