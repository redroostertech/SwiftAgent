import Foundation
import SwiftAgentCore
import SwiftAgentServer
import SwiftAgentHTTPServer

// ─────────────────────────────────────────────────────────────
// MCPTestServer — a minimal MCP server for validating SwiftAgent
// client connectivity.
//
// Run:   swift run MCPTestServer
// Then connect from the SwiftAgent Tasks app:
//   Settings → URL: http://localhost:8080/mcp → Connect
//
// The server exposes three simple tools so you can verify
// the full round trip: discovery, form generation, invocation,
// and result rendering.
// ─────────────────────────────────────────────────────────────

let port: UInt16 = 8080

let server = AgentServer(
    info: MCPImplementation(
        name: "MCP Test Server",
        version: "1.0.0"
    ),
    instructions: "A test server with three simple tools for validating MCP connectivity."
)

// Tool 1: echo — returns whatever you send
try await server.register(AgentTool(
    name: "echo",
    description: "Echo a message back. Useful for testing round-trip connectivity.",
    annotations: MCPToolAnnotations(readOnly: true, idempotent: true)
) {
    Parameter.string("message", description: "The message to echo back")
} handler: { args in
    let message = try args.string("message")
    return .text("Echo: \(message)")
})

// Tool 2: add — adds two numbers
try await server.register(AgentTool(
    name: "add",
    description: "Add two numbers together and return the sum.",
    annotations: MCPToolAnnotations(readOnly: true, idempotent: true)
) {
    Parameter.number("a", description: "First number")
    Parameter.number("b", description: "Second number")
} handler: { args in
    let a = try args.number("a")
    let b = try args.number("b")
    return .json(.object(["sum": .double(a + b)]))
})

// Tool 3: current_time — returns the current date and time
try await server.register(AgentTool(
    name: "current_time",
    description: "Get the current date and time on the server.",
    annotations: MCPToolAnnotations(readOnly: true, idempotent: false),
    handler: { _ in
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let now = formatter.string(from: Date())
        return .text(now)
    }
))

// Tool 4: greet — greeting with optional formality
try await server.register(AgentTool(
    name: "greet",
    description: "Generate a greeting for someone.",
    annotations: MCPToolAnnotations(readOnly: true, idempotent: true)
) {
    Parameter.string("name", description: "Person's name")
    Parameter.boolean("formal", description: "Use formal greeting", isRequired: false, default: false)
} handler: { args in
    let name = try args.string("name")
    let formal = args.optionalBoolean("formal") ?? false
    if formal {
        return .text("Good day, \(name). How may I be of assistance?")
    } else {
        return .text("Hey \(name)! 👋")
    }
})

// Wrap the server handler with logging so we can see what's happening.
let originalServer = server
let loggingTransport = HTTPServerTransport(port: port)
try await originalServer.start(transport: loggingTransport)

// Also log every request the server handles by wrapping it.
// (The HTTPServerTransport logs are internal; we add top-level visibility here.)
print("Server started. Listening for connections...")

print("""
    ┌──────────────────────────────────────────────┐
    │  MCP Test Server running                     │
    │                                              │
    │  URL: http://localhost:\(port)/mcp              │
    │  Tools: echo, add, current_time, greet       │
    │                                              │
    │  Connect from the SwiftAgent Tasks app:      │
    │  Settings → enter the URL above → Connect    │
    │                                              │
    │  Press Ctrl+C to stop.                       │
    └──────────────────────────────────────────────┘
    """)

// Keep running until killed.
let _ = await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in
    // Block forever. The server runs on its own tasks.
    // Ctrl+C terminates the process.
}
