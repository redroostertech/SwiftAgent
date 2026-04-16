import Foundation
import Network
import SwiftAgentCore

/// TCP client transport that speaks the SwiftAgent newline-delimited
/// JSON-RPC wire format to a `NetworkServerTransport` (or any
/// compatible peer).
///
/// Unlike the server side, the client is trivially long-lived: it
/// opens one `NWConnection` to the target endpoint, sends requests,
/// matches responses to pending continuations by JSON-RPC id, and
/// closes cleanly on ``close()``.
///
/// Use ``AgentServiceBrowser`` to discover the endpoint dynamically
/// via Bonjour, or pass a fixed host+port for testing and machine-local
/// scenarios.
public final class NetworkClientTransport: AgentClientTransport, @unchecked Sendable {
    private let endpoint: NWEndpoint
    private let queue = DispatchQueue(label: "app.mcp.client.network")
    private var connection: NWConnection?
    private var readerBuffer = Data()
    private var pending: [JSONRPCID: CheckedContinuation<JSONRPCResponse, any Error>] = [:]
    private var isClosed = false
    private let lock = NSLock()

    /// Small reference-type flag used to coordinate a one-shot
    /// continuation resume from multiple closure invocations on the
    /// `NWConnection` state-update handler.
    private final class Flag: @unchecked Sendable {
        var value = false
    }

    /// Build a client transport pointed at a concrete endpoint. Usually
    /// sourced from ``AgentServiceBrowser``.
    ///
    /// - Parameter endpoint: The network endpoint to connect to.
    public init(endpoint: NWEndpoint) {
        self.endpoint = endpoint
    }

    /// Convenience init for a host:port pair.
    public convenience init(host: String, port: UInt16) {
        self.init(endpoint: .hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? .any
        ))
    }

    // MARK: - AgentClientTransport

    public func send(_ request: JSONRPCRequest) async throws -> JSONRPCResponse {
        guard let id = request.id else {
            throw MCPError.custom(code: -32600, message: "send() requires a non-nil request id; use notify() for notifications")
        }
        try await ensureConnected()
        let payload = try JSONRPCFraming.encode(request)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSONRPCResponse, Error>) in
            lock.lock()
            if isClosed {
                lock.unlock()
                continuation.resume(throwing: MCPError.transportClosed)
                return
            }
            pending[id] = continuation
            lock.unlock()

            connection?.send(content: payload, completion: .contentProcessed { [weak self] error in
                if let error {
                    self?.failPending(id, with: error)
                }
            })
        }
    }

    public func notify(_ request: JSONRPCRequest) async throws {
        try await ensureConnected()
        let payload = try JSONRPCFraming.encode(request)
        connection?.send(content: payload, completion: .idempotent)
    }

    public func close() async {
        let waiters: [JSONRPCID: CheckedContinuation<JSONRPCResponse, any Error>] = lock.withLock {
            isClosed = true
            let snapshot = pending
            pending.removeAll()
            return snapshot
        }
        for (_, continuation) in waiters {
            continuation.resume(throwing: MCPError.transportClosed)
        }
        connection?.cancel()
        connection = nil
    }

    // MARK: - Connection management

    private func ensureConnected() async throws {
        if connection != nil { return }
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let connection = NWConnection(to: endpoint, using: parameters)
        self.connection = connection

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let resumed = Flag()
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if !resumed.value {
                        resumed.value = true
                        continuation.resume()
                    }
                    self?.beginReading(connection)
                case .failed(let error):
                    if !resumed.value {
                        resumed.value = true
                        continuation.resume(throwing: error)
                    }
                case .cancelled:
                    self?.teardown()
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    private func beginReading(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.readerBuffer.append(data)
                self.drainReaderBuffer()
            }
            if error != nil || isComplete {
                self.teardown()
                return
            }
            self.beginReading(connection)
        }
    }

    private func drainReaderBuffer() {
        while let newline = readerBuffer.firstIndex(of: 0x0A) {
            let line = readerBuffer[readerBuffer.startIndex..<newline]
            readerBuffer.removeSubrange(readerBuffer.startIndex...newline)
            if let response = try? JSONDecoder.swiftAgent.decode(JSONRPCResponse.self, from: Data(line)),
               let id = response.id {
                completePending(id, with: response)
            }
        }
    }

    private func completePending(_ id: JSONRPCID, with response: JSONRPCResponse) {
        lock.lock()
        let continuation = pending.removeValue(forKey: id)
        lock.unlock()
        continuation?.resume(returning: response)
    }

    private func failPending(_ id: JSONRPCID, with error: any Error) {
        lock.lock()
        let continuation = pending.removeValue(forKey: id)
        lock.unlock()
        continuation?.resume(throwing: error)
    }

    private func teardown() {
        lock.lock()
        let waiters = pending
        pending.removeAll()
        isClosed = true
        lock.unlock()
        for (_, continuation) in waiters {
            continuation.resume(throwing: MCPError.transportClosed)
        }
        connection = nil
    }
}
