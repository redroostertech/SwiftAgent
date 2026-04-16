import Foundation

/// Incrementally parses a Server-Sent Events byte stream into discrete events.
///
/// Feed raw bytes from an HTTP `text/event-stream` response body into
/// ``feed(_:)`` and collect the resulting ``SSEEvent`` values. The reader
/// handles partial lines across chunk boundaries — callers do not need to
/// pre-buffer or align on newline boundaries.
///
/// ### Thread safety
///
/// `SSEReader` is **not** thread-safe. Callers must serialize access — a
/// typical pattern is to call ``feed(_:)`` from a single `URLSession`
/// delegate callback or an `AsyncBytes` iteration loop.
///
/// - SeeAlso: [Server-Sent Events — W3C](https://html.spec.whatwg.org/multipage/server-sent-events.html)
public struct SSEReader: Sendable {

    /// A single parsed Server-Sent Events event.
    public struct SSEEvent: Sendable, Equatable {
        /// The event type (from the `event:` field), or `"message"` when
        /// no explicit type was specified.
        public let event: String

        /// The concatenated data payload. Multiple `data:` lines are joined
        /// with newlines per the SSE specification.
        public let data: String

        /// The event id (from the `id:` field), if present.
        public let id: String?
    }

    // MARK: - Internal state

    /// Accumulates bytes until a complete line is available.
    private var lineBuffer: String = ""

    /// Fields collected for the event currently being assembled.
    private var currentEvent: String?
    private var currentData: [String] = []
    private var currentId: String?

    /// Build a new, empty SSE reader.
    public init() {}

    // MARK: - Public API

    /// Feed a chunk of bytes and return any complete events found.
    ///
    /// The caller should pass each data chunk exactly as received from
    /// the HTTP response body. Partial lines are buffered internally
    /// until the next newline arrives.
    ///
    /// - Parameter chunk: Raw bytes from the event stream.
    /// - Returns: Zero or more fully-parsed events.
    public mutating func feed(_ chunk: Data) -> [SSEEvent] {
        guard let text = String(data: chunk, encoding: .utf8) else { return [] }
        lineBuffer += text
        return drainLines()
    }

    // MARK: - Line-level parsing

    /// Drain complete lines from the buffer and dispatch them.
    private mutating func drainLines() -> [SSEEvent] {
        var events: [SSEEvent] = []

        while let newlineRange = lineBuffer.rangeOfCharacter(from: .newlines) {
            let line = String(lineBuffer[lineBuffer.startIndex..<newlineRange.lowerBound])
            lineBuffer = String(lineBuffer[newlineRange.upperBound...])

            // Handle \r\n: rangeOfCharacter(.newlines) matches \r or \n
            // individually. If it matched \r and the next char is \n, consume
            // the \n so a \r\n pair doesn't produce a spurious blank line.
            if lineBuffer.first == "\n" {
                lineBuffer.removeFirst()
            }

            if line.isEmpty {
                // Blank line: dispatch accumulated fields as an event.
                if !currentData.isEmpty {
                    let event = SSEEvent(
                        event: currentEvent ?? "message",
                        data: currentData.joined(separator: "\n"),
                        id: currentId
                    )
                    events.append(event)
                }
                currentEvent = nil
                currentData = []
                currentId = nil
            } else if line.hasPrefix(":") {
                // Comment line — ignore per spec.
                continue
            } else {
                parseLine(line)
            }
        }

        return events
    }

    /// Parse a single non-empty, non-comment field line.
    private mutating func parseLine(_ line: String) {
        let field: String
        let value: String

        if let colonIndex = line.firstIndex(of: ":") {
            field = String(line[line.startIndex..<colonIndex])
            var rest = line[line.index(after: colonIndex)...]
            // Strip a single leading space after the colon, per spec.
            if rest.first == " " {
                rest = rest.dropFirst()
            }
            value = String(rest)
        } else {
            // Line with no colon: treat entire line as field name, empty value.
            field = line
            value = ""
        }

        switch field {
        case "event":
            currentEvent = value
        case "data":
            currentData.append(value)
        case "id":
            currentId = value
        case "retry":
            // Retry is informational; we do not act on it.
            break
        default:
            // Unknown fields are ignored per spec.
            break
        }
    }
}
