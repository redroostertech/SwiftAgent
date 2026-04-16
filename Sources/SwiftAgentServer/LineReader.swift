import Foundation
import Network

/// Newline-delimited message reader for an `NWConnection`.
///
/// AppMCP frames each JSON-RPC message on a single line terminated by
/// `\n` (LF, `0x0A`). `LineReader` bridges that framing onto the
/// callback-based `NWConnection.receive` API: it accumulates bytes,
/// emits one `Data` per completed line, and re-arms the next read
/// automatically until the connection closes.
///
/// The reader is intentionally minimal — no backpressure, no windowing
/// — because AppMCP payloads are tiny (tool calls, not file transfers).
/// A single line is bounded by whatever the peer can generate in one
/// JSON object; in practice that is well under 1 MB.
final class LineReader: @unchecked Sendable {
    /// Per-line callback invoked each time the reader has accumulated a
    /// full newline-terminated message. Runs on the reader's dispatch
    /// queue; callers should hop to an actor as needed.
    typealias LineHandler = @Sendable (Data) async -> Void

    private let connection: NWConnection
    private let queue: DispatchQueue
    private let lineHandler: LineHandler
    private var buffer = Data()
    private let maximumLineLength: Int

    /// Build a reader for the given connection.
    ///
    /// - Parameters:
    ///   - connection: The `NWConnection` to read from.
    ///   - queue: The dispatch queue the reader schedules its reads on.
    ///   - maximumLineLength: Upper bound on a single framed message.
    ///     Guards against a peer that forgets to send a newline.
    ///   - lineHandler: Called for each complete line.
    init(
        connection: NWConnection,
        queue: DispatchQueue,
        maximumLineLength: Int = 1 << 20,
        lineHandler: @escaping LineHandler
    ) {
        self.connection = connection
        self.queue = queue
        self.lineHandler = lineHandler
        self.maximumLineLength = maximumLineLength
    }

    /// Kick off the read loop. Safe to call exactly once per reader.
    func resume() {
        scheduleReceive()
    }

    private func scheduleReceive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.drain()
            }
            if let error = error as NSError?, error.code != 0 {
                self.connection.cancel()
                return
            }
            if isComplete {
                self.connection.cancel()
                return
            }
            if self.buffer.count > self.maximumLineLength {
                // Protect the process from a runaway peer.
                self.connection.cancel()
                return
            }
            self.scheduleReceive()
        }
    }

    private func drain() {
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            let payload = Data(line)
            let handler = lineHandler
            Task { await handler(payload) }
        }
    }
}
