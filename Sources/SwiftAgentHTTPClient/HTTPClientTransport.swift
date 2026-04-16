import Foundation
import SwiftAgentCore
import SwiftAgentClient

/// MCP Streamable HTTP client transport.
///
/// Implements the client side of the MCP 2025-06-18 Streamable HTTP
/// transport specification. Each JSON-RPC request is sent as the body
/// of an HTTP POST to the server's MCP endpoint. Responses arrive as
/// either a plain `application/json` body or as a `text/event-stream`
/// (SSE) payload.
///
/// Session continuity is maintained via the `Mcp-Session-Id` header:
/// the server provides the id on its first response, and the client
/// echoes it back on every subsequent request.
///
/// Uses `URLSession` exclusively — no Network.framework dependency — so
/// it works on every Apple platform including watchOS where
/// `NWConnection` is unavailable.
///
/// ### Thread safety
///
/// All mutable state is guarded by an `NSLock`. The class is
/// `@unchecked Sendable` because `URLSession` manages its own thread
/// pool internally and the lock serializes access to shared fields.
public final class HTTPClientTransport: AgentClientTransport, @unchecked Sendable {

    // MARK: - Configuration

    /// The server's MCP endpoint URL (e.g. `http://localhost:3000/mcp`).
    private let url: URL

    // MARK: - Runtime state (guarded by `lock`)

    private let lock = NSLock()
    private let session: URLSession
    private var sessionId: String?
    private var isClosed = false

    // MARK: - Initializer

    /// Build an HTTP client transport pointed at a remote MCP server.
    ///
    /// - Parameter url: The server's MCP endpoint URL (e.g.
    ///   `http://localhost:3000/mcp`).
    public init(url: URL) {
        self.url = url
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: config)
    }

    // MARK: - AgentClientTransport

    /// Send a JSON-RPC request and wait for the matching response.
    ///
    /// The request is encoded as the HTTP POST body. The response is
    /// decoded from either a plain JSON body or the first `message`
    /// event of an SSE stream, depending on the server's
    /// `Content-Type`.
    ///
    /// - Parameter request: The request to send. Must have a non-nil id.
    /// - Returns: The server's JSON-RPC response.
    /// - Throws: ``MCPError/transportClosed`` if the transport has been
    ///   closed, or any transport/network error.
    public func send(_ request: JSONRPCRequest) async throws -> JSONRPCResponse {
        guard !isTransportClosed else { throw MCPError.transportClosed }

        let (data, httpResponse) = try await performPOST(request)

        // Capture session id from the server.
        captureSessionId(from: httpResponse)

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""

        if contentType.contains("text/event-stream") {
            return try decodeSSEResponse(from: data)
        } else {
            return try JSONDecoder.swiftAgent.decode(JSONRPCResponse.self, from: data)
        }
    }

    /// Send a notification (a request with no id) without waiting for a
    /// response.
    ///
    /// - Parameter request: The notification to send. Its `id` must be `nil`.
    /// - Throws: ``MCPError/transportClosed`` if the transport has been
    ///   closed, or any transport/network error.
    public func notify(_ request: JSONRPCRequest) async throws {
        guard !isTransportClosed else { throw MCPError.transportClosed }

        let (_, httpResponse) = try await performPOST(request)
        captureSessionId(from: httpResponse)
    }

    /// Close the transport and release resources.
    ///
    /// Attempts to send a `DELETE` to the server to terminate the MCP
    /// session, then invalidates the underlying `URLSession`. Any
    /// in-flight requests will fail with a cancelled error.
    ///
    /// Safe to call multiple times; subsequent calls are no-ops.
    public func close() async {
        let (wasClosed, currentSessionId) = lock.withLock {
            let was = isClosed
            isClosed = true
            let sid = sessionId
            return (was, sid)
        }

        guard !wasClosed else { return }

        // Best-effort session termination.
        if let currentSessionId {
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue(currentSessionId, forHTTPHeaderField: "Mcp-Session-Id")
            _ = try? await session.data(for: request)
        }

        session.invalidateAndCancel()
    }

    // MARK: - Internal helpers

    /// Whether the transport has been closed.
    private var isTransportClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isClosed
    }

    /// Build and execute an HTTP POST carrying a JSON-RPC payload.
    private func performPOST(_ rpcRequest: JSONRPCRequest) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let sid = lock.withLock { sessionId }

        if let sid {
            request.setValue(sid, forHTTPHeaderField: "Mcp-Session-Id")
        }

        let body = try JSONEncoder.swiftAgent.encode(rpcRequest)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPError.custom(code: -32010, message: "Non-HTTP response received")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? "No body"
            throw MCPError.custom(
                code: -32010,
                message: "HTTP \(httpResponse.statusCode): \(bodyText)"
            )
        }

        return (data, httpResponse)
    }

    /// Extract and store the `Mcp-Session-Id` from a server response.
    private func captureSessionId(from response: HTTPURLResponse) {
        if let sid = response.value(forHTTPHeaderField: "Mcp-Session-Id") {
            lock.lock()
            sessionId = sid
            lock.unlock()
        }
    }

    /// Decode a JSON-RPC response from an SSE event stream body.
    ///
    /// Parses the first `message` event from the stream and decodes its
    /// `data` field as a ``JSONRPCResponse``.
    private func decodeSSEResponse(from data: Data) throws -> JSONRPCResponse {
        var reader = SSEReader()
        let events = reader.feed(data)

        guard let first = events.first(where: { $0.event == "message" }),
              let jsonData = first.data.data(using: .utf8) else {
            throw MCPError.custom(
                code: -32010,
                message: "No valid message event found in SSE response"
            )
        }

        return try JSONDecoder.swiftAgent.decode(JSONRPCResponse.self, from: jsonData)
    }
}
