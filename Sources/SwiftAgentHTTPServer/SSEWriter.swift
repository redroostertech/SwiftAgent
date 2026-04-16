import Foundation

/// Formats data into the Server-Sent Events wire format (W3C EventSource).
///
/// Each SSE message consists of one or more field lines (`event:`, `data:`,
/// `id:`, `retry:`) terminated by a blank line (`\n\n`). This writer
/// produces the raw bytes for a single event and is intentionally
/// stateless — callers are responsible for writing the bytes to the
/// appropriate output channel (an HTTP response body, a file, etc.).
///
/// ### Wire format
///
/// ```
/// event: message\n
/// data: {"jsonrpc":"2.0",...}\n
/// \n
/// ```
///
/// Multi-line `data` values are split across multiple `data:` lines per
/// the SSE specification.
///
/// - SeeAlso: [Server-Sent Events — W3C](https://html.spec.whatwg.org/multipage/server-sent-events.html)
public enum SSEWriter: Sendable {

    /// Format a single SSE event as UTF-8 bytes.
    ///
    /// - Parameters:
    ///   - event: The optional event type (maps to the `event:` field).
    ///     When `nil`, the EventSource default type `"message"` is implied
    ///     on the receiver side and no `event:` line is emitted.
    ///   - data: The payload string. Multi-line values are automatically
    ///     split across separate `data:` lines.
    ///   - id: An optional event id (maps to the `id:` field).
    /// - Returns: The fully-framed SSE event, ready to write to the wire.
    public static func frame(
        event: String? = nil,
        data: String,
        id: String? = nil
    ) -> Data {
        var output = ""

        if let event {
            output += "event: \(event)\n"
        }

        if let id {
            output += "id: \(id)\n"
        }

        // Each line of the data payload gets its own `data:` prefix.
        let lines = data.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines {
            output += "data: \(line)\n"
        }

        // Blank line terminates the event.
        output += "\n"

        return Data(output.utf8)
    }
}
