import Foundation
import SwiftAgentCore

/// The runtime host of an SwiftAgent server.
///
/// `AgentServer` owns three things:
///
/// 1. An ``AgentToolRegistry`` containing every tool the server exposes.
/// 2. The initialize-handshake lifecycle — exactly one handshake must
///    succeed before any tool can be called, and subsequent handshakes
///    are rejected.
/// 3. The JSON-RPC dispatcher that maps incoming requests onto either
///    the lifecycle methods or a registered tool.
///
/// The server is an `actor`, so concurrent requests (from multiple
/// transports or multiple connections on the same transport) are
/// serialized safely without explicit locks.
///
/// ### Minimal usage
///
/// ```swift
/// let server = AgentServer(info: MCPImplementation(
///     name: "My App",
///     version: "1.0.0",
///     bundleIdentifier: Bundle.main.bundleIdentifier
/// ))
///
/// try await server.register(myTool)
/// try await server.start(transport: InProcessServerTransport(...))
/// ```
///
/// The default-shared instance ``shared`` exists for apps that want a
/// single global server without plumbing one around. Tests and
/// multi-server scenarios should construct their own instances.
public actor AgentServer {
    /// Process-global default server. Safe to use from any thread.
    ///
    /// Apps that only ever expose one SwiftAgent surface can register all
    /// their tools against ``shared`` at launch; tests should prefer
    /// building a dedicated instance to avoid cross-test state.
    public static let shared = AgentServer(
        info: MCPImplementation(
            name: "SwiftAgent Server",
            version: "1.0.0",
            bundleIdentifier: Bundle.main.bundleIdentifier
        )
    )

    /// Identity of this server, echoed during the initialize handshake.
    public nonisolated let info: MCPImplementation

    /// Optional free-form instructions surfaced to LLM clients in the
    /// initialize result, typically describing how to best use the tools.
    public let instructions: String?

    private var registry = AgentToolRegistry()
    private var isInitialized = false
    private var activeTransport: (any AgentServerTransport)?

    /// Build a server with the given identity.
    ///
    /// - Parameters:
    ///   - info: The server's public identity.
    ///   - instructions: Optional free-form guidance for LLM clients.
    public init(info: MCPImplementation, instructions: String? = nil) {
        self.info = info
        self.instructions = instructions
    }

    // MARK: - Tool registration

    /// Register a tool for this server.
    ///
    /// - Parameter tool: The tool to expose.
    /// - Throws: ``MCPError`` on duplicate registration.
    public func register(_ tool: AgentTool) throws {
        try registry.register(tool)
    }

    /// Replace any existing tool of the same name, or register a new one
    /// if the name is not taken. Intended for hot reloads during
    /// development.
    public func replace(_ tool: AgentTool) {
        registry.replace(tool)
    }

    /// Unregister a tool by name. No-op if no tool with that name is
    /// registered.
    public func unregister(_ toolName: String) {
        registry.unregister(toolName)
    }

    /// The number of tools currently exposed by this server.
    public var toolCount: Int { registry.count }

    /// Snapshot of the tool descriptors this server currently exposes,
    /// in registration order.
    public var toolDescriptors: [MCPToolDescriptor] { registry.descriptors }

    // MARK: - Session lifecycle

    /// Start the server on top of a transport. The server begins
    /// accepting requests immediately; the call returns once the
    /// transport has finished its own startup work.
    ///
    /// - Parameter transport: The transport to host the server on.
    /// - Throws: Any error raised while starting the transport.
    public func start(transport: any AgentServerTransport) async throws {
        self.activeTransport = transport
        let handler: @Sendable (JSONRPCRequest) async -> JSONRPCResponse? = { [weak self] request in
            guard let self else { return nil }
            return await self.handle(request)
        }
        try await transport.start(handler: handler)
    }

    /// Stop the server and its transport. After stopping, the server
    /// retains its tool registry so it can be restarted against a new
    /// transport without losing state.
    public func stop() async {
        await activeTransport?.stop()
        activeTransport = nil
        isInitialized = false
    }

    // MARK: - Request dispatch

    /// The top-level JSON-RPC dispatcher. Invoked by transports for
    /// every inbound request. Notifications (requests without an id)
    /// always return `nil`; calls return a ``JSONRPCResponse``.
    public func handle(_ request: JSONRPCRequest) async -> JSONRPCResponse? {
        if request.isNotification {
            await handleNotification(request)
            return nil
        }
        do {
            let result = try await route(request)
            return JSONRPCResponse(id: request.id, result: result)
        } catch let error as MCPError {
            return JSONRPCResponse(id: request.id, error: error.jsonRPCError)
        } catch let error as JSONRPCError {
            return JSONRPCResponse(id: request.id, error: error)
        } catch {
            return JSONRPCResponse(
                id: request.id,
                error: JSONRPCError(
                    code: -32603,
                    message: "Internal error: \(error.localizedDescription)"
                )
            )
        }
    }

    private func handleNotification(_ request: JSONRPCRequest) async {
        switch request.method {
        case MCPMethod.initialized:
            // Client signals it has processed the initialize result.
            // Nothing to do — we already transitioned to ready after
            // returning the initialize response.
            break
        case MCPMethod.cancelled:
            // Cancellation is best-effort; real handler wiring comes
            // with streaming tool support (phase 2).
            break
        default:
            break
        }
    }

    private func route(_ request: JSONRPCRequest) async throws -> JSONValue {
        switch request.method {
        case MCPMethod.initialize:
            return try handleInitialize(request.params)

        case MCPMethod.ping:
            return .object([:])

        case MCPMethod.shutdown:
            isInitialized = false
            return .object([:])

        case MCPMethod.listTools:
            try requireInitialized()
            let result = MCPListToolsResult(tools: registry.descriptors)
            return try encodeToJSONValue(result)

        case MCPMethod.callTool:
            try requireInitialized()
            let params: MCPCallToolParams = try decodeParams(request.params)
            let result = try await invokeTool(params)
            return try encodeToJSONValue(result)

        default:
            throw JSONRPCError.methodNotFound(request.method)
        }
    }

    private func handleInitialize(_ params: JSONValue?) throws -> JSONValue {
        if isInitialized {
            throw MCPError.alreadyInitialized
        }
        let decoded: MCPInitializeParams = try decodeParams(params)
        guard AgentProtocol.supportedVersions.contains(decoded.protocolVersion) else {
            throw MCPError.unsupportedProtocolVersion(
                offered: decoded.protocolVersion,
                supported: AgentProtocol.supportedVersions
            )
        }
        isInitialized = true
        let result = MCPInitializeResult(
            protocolVersion: AgentProtocol.version,
            serverInfo: info,
            capabilities: MCPServerCapabilities(
                tools: MCPToolsCapability(listChanged: true)
            ),
            instructions: instructions
        )
        return try encodeToJSONValue(result)
    }

    private func requireInitialized() throws {
        guard isInitialized else { throw MCPError.notInitialized }
    }

    private func invokeTool(_ params: MCPCallToolParams) async throws -> MCPCallToolResult {
        guard let tool = registry.tool(named: params.name) else {
            throw MCPError.toolNotFound(name: params.name)
        }
        // Schema-level validation.
        if let args = params.arguments {
            let errors = tool.descriptor.inputSchema.validate(args)
            if !errors.isEmpty {
                throw MCPError.invalidToolArguments(
                    name: params.name,
                    reason: errors.joined(separator: "; ")
                )
            }
        }
        let arguments = AgentToolArguments(
            raw: params.arguments,
            toolName: tool.name
        )
        do {
            return try await tool.handler(arguments)
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.toolExecutionFailed(
                name: tool.name,
                message: error.localizedDescription
            )
        }
    }

    // MARK: - Codable bridging

    private func decodeParams<T: Decodable>(_ params: JSONValue?) throws -> T {
        let value = params ?? .object([:])
        let data = try JSONEncoder.swiftAgent.encode(value)
        return try JSONDecoder.swiftAgent.decode(T.self, from: data)
    }

    private func encodeToJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try JSONEncoder.swiftAgent.encode(value)
        return try JSONDecoder.swiftAgent.decode(JSONValue.self, from: data)
    }
}
