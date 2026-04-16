import Foundation
import SwiftAgentCore

/// The agent-side entry point for talking to an AppMCP server.
///
/// `AgentClient` is the counterpart to ``AgentServer``: it performs
/// the initialize handshake, manages JSON-RPC request ids, maps
/// convenient Swift methods onto the wire protocol, and translates
/// error responses into typed `throws`. A client instance corresponds
/// to one logical session; close it when done.
///
/// ### Typical usage
///
/// ```swift
/// let client = AgentClient(
///     info: MCPImplementation(name: "My Agent", version: "1.0"),
///     transport: someTransport
/// )
/// try await client.initialize()
///
/// let tools = try await client.listTools()
/// for descriptor in tools {
///     print(descriptor.name, descriptor.description)
/// }
///
/// let result = try await client.callTool(
///     name: "create_note",
///     arguments: .object([
///         "title": "Hello",
///         "body": "World"
///     ])
/// )
///
/// await client.close()
/// ```
///
/// The client is an `actor`, so concurrent calls from multiple tasks
/// are serialized safely at the request-id allocator. Transports that
/// are themselves sequential (in-process, single-connection network)
/// get automatic head-of-line ordering; transports that multiplex can
/// reorder responses and still match them to requests via the id.
public actor AgentClient {
    /// Identity of this client, sent in the initialize handshake.
    public nonisolated let info: MCPImplementation

    /// Server identity, populated after ``initialize()`` completes.
    public private(set) var serverInfo: MCPImplementation?

    /// Server capabilities, populated after ``initialize()`` completes.
    public private(set) var serverCapabilities: MCPServerCapabilities?

    /// Server instructions, populated after ``initialize()`` completes.
    public private(set) var serverInstructions: String?

    private let transport: any AgentClientTransport
    private var nextRequestId: Int64 = 1
    private var isInitialized = false

    /// Build a client over the supplied transport.
    ///
    /// - Parameters:
    ///   - info: Identity of this client (name, version, optional bundle id).
    ///   - transport: The transport to speak over.
    public init(info: MCPImplementation, transport: any AgentClientTransport) {
        self.info = info
        self.transport = transport
    }

    // MARK: - Session lifecycle

    /// Perform the initialize handshake with the server. Must be called
    /// once before any other method; subsequent calls throw
    /// ``MCPError/alreadyInitialized``.
    ///
    /// - Throws: ``MCPError`` on protocol errors, or any transport error.
    public func initialize() async throws {
        if isInitialized {
            throw MCPError.alreadyInitialized
        }
        let params = MCPInitializeParams(
            protocolVersion: AgentProtocol.version,
            clientInfo: info,
            capabilities: MCPClientCapabilities()
        )
        let result: MCPInitializeResult = try await call(
            method: MCPMethod.initialize,
            params: params
        )
        self.serverInfo = result.serverInfo
        self.serverCapabilities = result.capabilities
        self.serverInstructions = result.instructions
        self.isInitialized = true

        // Fire-and-forget notifications/initialized so the server knows
        // the client has processed the handshake.
        let notify = JSONRPCRequest(id: nil, method: MCPMethod.initialized, params: nil)
        try await transport.notify(notify)
    }

    /// Close the session, release transport resources, and forget any
    /// negotiated state. Idempotent.
    public func close() async {
        await transport.close()
        isInitialized = false
        serverInfo = nil
        serverCapabilities = nil
        serverInstructions = nil
    }

    /// Health check. Sends a `ping` request and awaits the empty result.
    public func ping() async throws {
        try requireInitialized()
        let _: JSONValue = try await call(method: MCPMethod.ping, params: Optional<JSONValue>.none)
    }

    // MARK: - Tools

    /// Fetch the tool catalog from the server.
    ///
    /// - Returns: The ordered list of tools the server currently exposes.
    public func listTools() async throws -> [MCPToolDescriptor] {
        try requireInitialized()
        let result: MCPListToolsResult = try await call(
            method: MCPMethod.listTools,
            params: Optional<JSONValue>.none
        )
        return result.tools
    }

    /// Invoke a tool on the server with the supplied arguments.
    ///
    /// - Parameters:
    ///   - name: The tool's machine name.
    ///   - arguments: The arguments object. Passing `nil` is equivalent
    ///     to passing an empty object.
    /// - Returns: The tool's structured result.
    /// - Throws: ``MCPError/toolNotFound(name:)`` if the server does not
    ///   know that tool; ``MCPError/invalidToolArguments(name:reason:)``
    ///   if the arguments do not match the tool's schema;
    ///   ``MCPError/toolExecutionFailed(name:message:)`` on a runtime
    ///   error inside the tool handler; other ``MCPError`` cases on
    ///   protocol issues; transport errors propagate verbatim.
    public func callTool(name: String, arguments: JSONValue? = nil) async throws -> MCPCallToolResult {
        try requireInitialized()
        let params = MCPCallToolParams(name: name, arguments: arguments)
        return try await call(method: MCPMethod.callTool, params: params)
    }

    // MARK: - Private helpers

    private func requireInitialized() throws {
        guard isInitialized else { throw MCPError.notInitialized }
    }

    private func call<Params: Encodable, Result: Decodable>(
        method: String,
        params: Params
    ) async throws -> Result {
        let paramsJSON = try encodeToJSONValue(params)
        let id = allocateId()
        let request = JSONRPCRequest(id: .int(id), method: method, params: paramsJSON)
        let response = try await transport.send(request)
        if let error = response.error {
            throw error
        }
        let resultJSON = response.result ?? .object([:])
        return try decodeJSONValue(resultJSON)
    }

    private func allocateId() -> Int64 {
        defer { nextRequestId += 1 }
        return nextRequestId
    }

    private func encodeToJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
        if let optional = value as? Optional<JSONValue>, case .none = optional {
            return .object([:])
        }
        let data = try JSONEncoder.swiftAgent.encode(value)
        return try JSONDecoder.swiftAgent.decode(JSONValue.self, from: data)
    }

    private func decodeJSONValue<T: Decodable>(_ value: JSONValue) throws -> T {
        let data = try JSONEncoder.swiftAgent.encode(value)
        return try JSONDecoder.swiftAgent.decode(T.self, from: data)
    }
}
