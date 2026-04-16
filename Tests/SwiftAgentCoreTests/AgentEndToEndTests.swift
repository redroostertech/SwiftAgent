import XCTest
@testable import SwiftAgentCore
@testable import SwiftAgentServer
@testable import SwiftAgentClient

/// End-to-end tests that run a real ``AgentServer`` and
/// ``AgentClient`` through the in-process transport pair.
///
/// These tests exist to catch regressions in the pieces that are only
/// visible when the whole stack runs together: initialize handshake
/// negotiation, tool descriptor generation, argument validation,
/// handler dispatch, and error translation.
final class AgentEndToEndTests: XCTestCase {
    // MARK: - Helpers

    /// Build a server pre-populated with a few well-known tools, wire
    /// up a client, and return both so the test can exercise whichever
    /// call path it cares about.
    private func makeSession() async throws -> (server: AgentServer, client: AgentClient) {
        let server = AgentServer(
            info: MCPImplementation(name: "Test Server", version: "1.0.0"),
            instructions: "Test instructions for the agent."
        )

        try await server.register(AppMCPTool(
            name: "echo",
            description: "Echo a string back.",
            annotations: MCPToolAnnotations(readOnly: true, idempotent: true)
        ) {
            Parameter.string("message", description: "The message to echo back")
        } handler: { args in
            let message = try args.string("message")
            return .text(message)
        })

        try await server.register(AppMCPTool(
            name: "add",
            description: "Add two integers together.",
            annotations: MCPToolAnnotations(readOnly: true, idempotent: true)
        ) {
            Parameter.integer("a", description: "First addend")
            Parameter.integer("b", description: "Second addend")
        } handler: { args in
            let a = try args.integer("a")
            let b = try args.integer("b")
            return .json(.object(["sum": .int(a + b)]))
        })

        let serverTransport = InProcessServerTransport()
        try await server.start(transport: serverTransport)

        let clientTransport = InProcessClientTransport { request in
            await serverTransport.deliver(request)
        }
        let client = AgentClient(
            info: MCPImplementation(name: "Test Client", version: "1.0.0"),
            transport: clientTransport
        )
        try await client.initialize()
        return (server, client)
    }

    // MARK: - Tests

    func testInitializeHandshakeExchangesMetadata() async throws {
        let (server, client) = try await makeSession()
        _ = server // keep alive for the duration of the test
        let serverInfo = await client.serverInfo
        XCTAssertEqual(serverInfo?.name, "Test Server")
        let instructions = await client.serverInstructions
        XCTAssertEqual(instructions, "Test instructions for the agent.")
        let capabilities = await client.serverCapabilities
        XCTAssertNotNil(capabilities?.tools)
    }

    func testListToolsReturnsRegisteredDescriptors() async throws {
        let (server, client) = try await makeSession()
        _ = server // keep alive for the duration of the test
        let tools = try await client.listTools()
        let names = Set(tools.map(\.name))
        XCTAssertEqual(names, ["echo", "add"])
        let echo = tools.first { $0.name == "echo" }
        XCTAssertEqual(echo?.annotations?.readOnly, true)
        XCTAssertNotNil(echo?.inputSchema.properties?["message"])
    }

    func testCallEchoRoundTripsMessage() async throws {
        let (server, client) = try await makeSession()
        _ = server // keep alive for the duration of the test
        let result = try await client.callTool(
            name: "echo",
            arguments: .object(["message": .string("hello")])
        )
        XCTAssertFalse(result.isError)
        if case .text(let text) = result.content.first {
            XCTAssertEqual(text, "hello")
        } else {
            XCTFail("expected text content, got \(result.content)")
        }
    }

    func testCallAddReturnsStructuredJSON() async throws {
        let (server, client) = try await makeSession()
        _ = server // keep alive for the duration of the test
        let result = try await client.callTool(
            name: "add",
            arguments: .object(["a": .int(2), "b": .int(3)])
        )
        XCTAssertFalse(result.isError)
        XCTAssertEqual(result.structured, .object(["sum": .int(5)]))
    }

    func testCallingUnknownToolThrowsToolNotFound() async throws {
        let (server, client) = try await makeSession()
        _ = server // keep alive for the duration of the test
        do {
            _ = try await client.callTool(name: "nope", arguments: nil)
            XCTFail("expected tool-not-found error")
        } catch let error as JSONRPCError {
            XCTAssertEqual(error.code, -32100)
        }
    }

    func testMissingRequiredArgumentThrowsInvalidArguments() async throws {
        let (server, client) = try await makeSession()
        _ = server // keep alive for the duration of the test
        do {
            _ = try await client.callTool(name: "echo", arguments: .object([:]))
            XCTFail("expected invalid-arguments error")
        } catch let error as JSONRPCError {
            XCTAssertEqual(error.code, -32102)
        }
    }

    func testWrongTypedArgumentThrowsInvalidArguments() async throws {
        let (server, client) = try await makeSession()
        _ = server // keep alive for the duration of the test
        do {
            _ = try await client.callTool(
                name: "add",
                arguments: .object(["a": .string("nope"), "b": .int(1)])
            )
            XCTFail("expected invalid-arguments error")
        } catch let error as JSONRPCError {
            XCTAssertEqual(error.code, -32102)
        }
    }
}
