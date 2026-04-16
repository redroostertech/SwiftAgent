import Foundation

/// Newline-delimited JSON-RPC framing used on byte-stream transports.
///
/// Each message is a single line of JSON terminated by `\n` (0x0A). This
/// matches MCP's stdio-transport framing and makes debugging with simple
/// tools (`nc`, `cat`, line-oriented tails) straightforward.
public enum JSONRPCFraming {
    /// The byte value separating framed messages on the wire. Always LF.
    public static let messageTerminator: UInt8 = 0x0A // '\n'

    /// Encode a request into a wire-ready line including the terminator.
    ///
    /// - Parameters:
    ///   - request: The request to encode.
    ///   - encoder: The JSON encoder to use. Defaults to ``JSONEncoder/appMCP``.
    /// - Returns: The encoded request with a trailing newline appended.
    /// - Throws: Any error propagated from the underlying encoder.
    public static func encode(_ request: JSONRPCRequest, encoder: JSONEncoder = .swiftAgent) throws -> Data {
        var data = try encoder.encode(request)
        data.append(messageTerminator)
        return data
    }

    /// Encode a response into a wire-ready line including the terminator.
    ///
    /// - Parameters:
    ///   - response: The response to encode.
    ///   - encoder: The JSON encoder to use. Defaults to ``JSONEncoder/appMCP``.
    /// - Returns: The encoded response with a trailing newline appended.
    /// - Throws: Any error propagated from the underlying encoder.
    public static func encode(_ response: JSONRPCResponse, encoder: JSONEncoder = .swiftAgent) throws -> Data {
        var data = try encoder.encode(response)
        data.append(messageTerminator)
        return data
    }
}
