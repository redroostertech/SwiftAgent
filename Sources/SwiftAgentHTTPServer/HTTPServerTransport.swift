import Foundation
import Network
import SwiftAgentCore
import SwiftAgentServer

/// MCP Streamable HTTP server transport.
///
/// Implements the server side of the MCP 2025-06-18 Streamable HTTP
/// transport specification. Clients POST JSON-RPC request bodies to a
/// configurable endpoint path (default `/mcp`). The server responds with:
///
/// - `application/json` for simple request/response round-trips.
/// - `text/event-stream` (SSE) when the server needs to push
///   notifications after the initial response.
///
/// Session identity is tracked via the `Mcp-Session-Id` response header.
/// Clients that echo it back on subsequent requests are routed to the
/// same logical session.
///
/// ### Networking layer
///
/// Uses `NWListener` with raw TCP and manual HTTP/1.1 parsing. This
/// avoids the `NWProtocolHTTP` API that requires macOS 15+, keeping
/// compatibility back to the package's macOS 14 deployment target.
///
/// ### Thread safety
///
/// All mutable state is guarded by an `NSLock`. The class is
/// `@unchecked Sendable` because `NWListener` and `NWConnection` are
/// reference types that dispatch their callbacks on the transport's
/// serial queue.
public final class HTTPServerTransport: AgentServerTransport, @unchecked Sendable {

    // MARK: - Configuration

    /// The TCP port to bind on. Pass `0` to let the OS pick an ephemeral port.
    private let port: UInt16

    /// The URL path where MCP requests are accepted. Defaults to `/mcp`.
    private let path: String

    // MARK: - Runtime state (guarded by `lock`)

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "swiftagent.http.server", qos: .userInitiated)
    private var listener: NWListener?
    private var connections: Set<ObjectIdentifier> = []
    private var connectionMap: [ObjectIdentifier: NWConnection] = [:]
    private var handler: RequestHandler?
    private var sessionId: String?

    // MARK: - Initializer

    /// Build an HTTP server transport on the specified port.
    ///
    /// - Parameters:
    ///   - port: The TCP port to bind on. Pass `0` (the default) to let
    ///     the OS assign an ephemeral port.
    ///   - path: The URL path that accepts MCP POST requests. Defaults
    ///     to `"/mcp"`.
    public init(port: UInt16 = 0, path: String = "/mcp") {
        self.port = port
        self.path = path
    }

    // MARK: - AgentServerTransport

    /// Begin accepting HTTP connections.
    ///
    /// The transport binds a TCP listener on the configured port and
    /// starts processing inbound HTTP requests. Returns once the listener
    /// is ready; further work happens asynchronously on the transport's
    /// internal dispatch queue.
    ///
    /// - Parameter handler: The server callback that consumes each
    ///   incoming JSON-RPC request and returns a response (or `nil`
    ///   for notifications).
    /// - Throws: ``MCPError`` if the listener cannot be created.
    public func start(handler: @escaping RequestHandler) async throws {
        lock.lock()
        self.handler = handler
        self.sessionId = UUID().uuidString
        lock.unlock()

        let parameters = NWParameters.tcp
        let nwPort: NWEndpoint.Port = port == 0
            ? .any
            : NWEndpoint.Port(rawValue: port) ?? .any

        let newListener: NWListener
        do {
            newListener = try NWListener(using: parameters, on: nwPort)
        } catch {
            throw MCPError.custom(
                code: -32020,
                message: "Failed to create NWListener: \(error.localizedDescription)"
            )
        }

        newListener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            var resumed = false
            newListener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if !resumed {
                        resumed = true
                        self?.lock.lock()
                        self?.listener = newListener
                        self?.lock.unlock()
                        continuation.resume()
                    }
                case .failed(let error):
                    if !resumed {
                        resumed = true
                        continuation.resume(throwing: MCPError.custom(
                            code: -32020,
                            message: "NWListener failed: \(error.localizedDescription)"
                        ))
                    }
                case .cancelled:
                    if !resumed {
                        resumed = true
                        continuation.resume(throwing: MCPError.transportClosed)
                    }
                default:
                    break
                }
            }
            newListener.start(queue: self.queue)
        }
    }

    /// Stop the transport, cancel all connections, and release resources.
    ///
    /// Safe to call multiple times; subsequent calls are no-ops.
    public func stop() async {
        lock.lock()
        let currentListener = listener
        let currentConnections = connectionMap
        listener = nil
        connectionMap.removeAll()
        connections.removeAll()
        handler = nil
        lock.unlock()

        for (_, conn) in currentConnections {
            conn.cancel()
        }
        currentListener?.cancel()
    }

    // MARK: - Connection lifecycle

    /// Accept a new TCP connection and begin reading HTTP data from it.
    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)

        lock.lock()
        connections.insert(id)
        connectionMap[id] = connection
        lock.unlock()

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.readRequest(from: connection)
            case .failed, .cancelled:
                self?.removeConnection(connection)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    /// Remove a connection from the active set.
    private func removeConnection(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        lock.lock()
        connections.remove(id)
        connectionMap.removeValue(forKey: id)
        lock.unlock()
    }

    // MARK: - HTTP/1.1 request reading

    /// Read a complete HTTP request from the connection.
    ///
    /// Accumulates data until a full set of headers plus body (determined
    /// by `Content-Length`) has been received, then dispatches the request.
    private func readRequest(from connection: NWConnection) {
        readAccumulated(connection: connection, buffer: Data()) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let requestData):
                self.handleHTTPRequest(requestData, on: connection)
            case .failure:
                self.sendErrorResponse(
                    status: "400 Bad Request",
                    body: "Malformed HTTP request",
                    on: connection
                )
            }
        }
    }

    /// Accumulate bytes from the connection until a complete HTTP request
    /// (headers + body based on Content-Length) is available.
    private func readAccumulated(
        connection: NWConnection,
        buffer: Data,
        completion: @escaping @Sendable (Result<Data, any Error>) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                completion(.failure(error))
                return
            }

            var accumulated = buffer
            if let data {
                accumulated.append(data)
            }

            // Check if we have complete headers.
            if let headerEnd = self.findHeaderEnd(in: accumulated) {
                let headerData = accumulated[accumulated.startIndex..<headerEnd]
                let bodyStart = headerEnd
                let contentLength = self.parseContentLength(from: headerData)
                let remainingBody = accumulated[bodyStart...]

                if remainingBody.count >= contentLength {
                    // Full request received.
                    completion(.success(accumulated))
                    return
                }
            }

            if isComplete {
                // Connection closed before full request.
                completion(.success(accumulated))
                return
            }

            // Need more data.
            self.readAccumulated(connection: connection, buffer: accumulated, completion: completion)
        }
    }

    /// Find the end of HTTP headers (the `\r\n\r\n` boundary).
    /// Returns the index of the first byte after the boundary.
    private func findHeaderEnd(in data: Data) -> Data.Index? {
        let separator: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A] // \r\n\r\n
        guard data.count >= separator.count else { return nil }

        for i in data.startIndex...(data.index(data.endIndex, offsetBy: -separator.count)) {
            if data[i] == separator[0],
               data[data.index(after: i)] == separator[1],
               data[data.index(i, offsetBy: 2)] == separator[2],
               data[data.index(i, offsetBy: 3)] == separator[3] {
                return data.index(i, offsetBy: separator.count)
            }
        }
        return nil
    }

    /// Extract the `Content-Length` value from raw header bytes.
    private func parseContentLength(from headerData: Data) -> Int {
        guard let headerString = String(data: Data(headerData), encoding: .utf8) else { return 0 }
        let lines = headerString.components(separatedBy: "\r\n")
        for line in lines {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                return Int(value) ?? 0
            }
        }
        return 0
    }

    // MARK: - HTTP request dispatch

    /// Parse and dispatch a complete HTTP request.
    private func handleHTTPRequest(_ data: Data, on connection: NWConnection) {
        guard let headerEnd = findHeaderEnd(in: data) else {
            sendErrorResponse(status: "400 Bad Request", body: "Incomplete headers", on: connection)
            return
        }

        let headerData = data[data.startIndex..<data.index(headerEnd, offsetBy: -4)]
        guard let headerString = String(data: Data(headerData), encoding: .utf8) else {
            sendErrorResponse(status: "400 Bad Request", body: "Invalid header encoding", on: connection)
            return
        }

        let headerLines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = headerLines.first else {
            sendErrorResponse(status: "400 Bad Request", body: "Missing request line", on: connection)
            return
        }

        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else {
            sendErrorResponse(status: "400 Bad Request", body: "Malformed request line", on: connection)
            return
        }

        let method = String(parts[0])
        let requestPath = String(parts[1])

        // Parse headers into a dictionary.
        var headers: [String: String] = [:]
        for line in headerLines.dropFirst() {
            if let colonIndex = line.firstIndex(of: ":") {
                let key = line[line.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        // Check Accept header for SSE support.
        let acceptsSSE = headers["accept"]?.contains("text/event-stream") ?? false

        // Route the request.
        guard method == "POST" else {
            if method == "DELETE" && requestPath == path {
                // Session termination per MCP spec.
                sendResponse(status: "200 OK", contentType: "text/plain", body: Data(), on: connection)
                return
            }
            sendErrorResponse(status: "405 Method Not Allowed", body: "Only POST is accepted", on: connection)
            return
        }

        guard requestPath == path || requestPath.hasPrefix(path + "?") else {
            sendErrorResponse(status: "404 Not Found", body: "Not found", on: connection)
            return
        }

        let body = data[headerEnd...]

        // Decode the JSON-RPC request.
        let request: JSONRPCRequest
        do {
            request = try JSONDecoder.swiftAgent.decode(JSONRPCRequest.self, from: Data(body))
        } catch {
            let rpcError = JSONRPCError.parseError(error.localizedDescription)
            let rpcResponse = JSONRPCResponse(id: nil, error: rpcError)
            sendJSONResponse(rpcResponse, on: connection)
            return
        }

        // Dispatch to the handler.
        lock.lock()
        let currentHandler = handler
        let currentSessionId = sessionId
        lock.unlock()

        guard let currentHandler else {
            sendErrorResponse(status: "503 Service Unavailable", body: "Server not started", on: connection)
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let response = await currentHandler(request)

            if let response {
                if acceptsSSE {
                    // Send as SSE for clients that requested it.
                    self.sendSSEResponse(response, sessionId: currentSessionId, on: connection)
                } else {
                    self.sendJSONResponse(response, sessionId: currentSessionId, on: connection)
                }
            } else {
                // Notification — no response body expected; send 202 Accepted.
                self.sendResponse(
                    status: "202 Accepted",
                    contentType: "text/plain",
                    body: Data(),
                    sessionId: currentSessionId,
                    on: connection
                )
            }
        }
    }

    // MARK: - HTTP response writing

    /// Send a JSON-RPC response as `application/json`.
    private func sendJSONResponse(
        _ response: JSONRPCResponse,
        sessionId: String? = nil,
        on connection: NWConnection
    ) {
        do {
            let body = try JSONEncoder.swiftAgent.encode(response)
            sendResponse(
                status: "200 OK",
                contentType: "application/json",
                body: body,
                sessionId: sessionId,
                on: connection
            )
        } catch {
            sendErrorResponse(
                status: "500 Internal Server Error",
                body: "Failed to encode response",
                on: connection
            )
        }
    }

    /// Send a JSON-RPC response wrapped in an SSE event stream.
    private func sendSSEResponse(
        _ response: JSONRPCResponse,
        sessionId: String? = nil,
        on connection: NWConnection
    ) {
        do {
            let jsonData = try JSONEncoder.swiftAgent.encode(response)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                sendErrorResponse(
                    status: "500 Internal Server Error",
                    body: "Encoding failure",
                    on: connection
                )
                return
            }

            let sseEvent = SSEWriter.frame(event: "message", data: jsonString)

            var headerString = "HTTP/1.1 200 OK\r\n"
            headerString += "Content-Type: text/event-stream\r\n"
            headerString += "Cache-Control: no-cache\r\n"
            headerString += "Connection: close\r\n"
            if let sessionId {
                headerString += "Mcp-Session-Id: \(sessionId)\r\n"
            }
            headerString += "\r\n"

            var payload = Data(headerString.utf8)
            payload.append(sseEvent)

            connection.send(content: payload, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
        } catch {
            sendErrorResponse(
                status: "500 Internal Server Error",
                body: "Failed to encode SSE response",
                on: connection
            )
        }
    }

    /// Send a raw HTTP response with the given status, content type, and body.
    private func sendResponse(
        status: String,
        contentType: String,
        body: Data,
        sessionId: String? = nil,
        on connection: NWConnection
    ) {
        var headerString = "HTTP/1.1 \(status)\r\n"
        headerString += "Content-Type: \(contentType)\r\n"
        headerString += "Content-Length: \(body.count)\r\n"
        if let sessionId {
            headerString += "Mcp-Session-Id: \(sessionId)\r\n"
        }
        headerString += "Connection: close\r\n"
        headerString += "\r\n"

        var payload = Data(headerString.utf8)
        payload.append(body)

        connection.send(content: payload, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// Convenience for sending a plain-text error response.
    private func sendErrorResponse(
        status: String,
        body: String,
        on connection: NWConnection
    ) {
        sendResponse(
            status: status,
            contentType: "text/plain; charset=utf-8",
            body: Data(body.utf8),
            on: connection
        )
    }
}
