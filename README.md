# SwiftAgent

A Swift-native, mobile-first agent-tool SDK for Apple platforms, with MCP as its interoperability layer.

**One tool declaration. Every integration surface. Zero duplication.**

This is a research project exploring how Apple platform apps can participate in the emerging LLM tool-calling ecosystem without maintaining parallel tool definitions for every framework, protocol, and model provider. The thesis is that a single annotated Swift struct should be enough to light up Siri, Shortcuts, Apple Intelligence, on-device LLMs, cloud LLMs (OpenAI, Anthropic), external MCP clients, and your own in-app agent loop, all from one source of truth.

---

## Table of Contents

- [What This Project Is](#what-this-project-is)
- [What This Project Is Not](#what-this-project-is-not)
- [Why We Are Exploring This](#why-we-are-exploring-this)
- [Architecture and Approach](#architecture-and-approach)
- [Package Structure](#package-structure)
- [How It All Works Together](#how-it-all-works-together)
- [Getting Started](#getting-started)
- [Building the Demo Apps](#building-the-demo-apps)
- [Running the MCP Test Server](#running-the-mcp-test-server)
- [Running the LLM Server (llama.cpp)](#running-the-llm-server-llamacpp)
- [Running the Agent Runner CLI](#running-the-agent-runner-cli)
- [Why Are the Servers Separate?](#why-are-the-servers-separate)
- [Testing and Verification](#testing-and-verification)
- [Test Model](#test-model)
- [Troubleshooting](#troubleshooting)
- [How This Scales](#how-this-scales)
- [What This Works With](#what-this-works-with)
- [Blog Posts / Build Journal](#blog-posts--build-journal)
- [Contributing](#contributing)
- [License](#license)

---

## What This Project Is

SwiftAgent is a research SDK that unifies the fragmented tool-declaration landscape on Apple platforms. In 2026, an iOS app that ships AI features ends up maintaining the same tool in four to seven different formats: an AppIntent for Siri, a Tool conformance for Foundation Models, OpenAI JSON for cloud calls, Anthropic JSON for cloud calls, MCP descriptors for external agents, and hand-rolled definitions for in-app agent loops. All of them describe the same function. They drift out of sync. Adding a parameter means updating it in six places.

SwiftAgent solves this with a macro-based approach. You write one annotated struct:

```swift
@AgentTool("Create a note with a title and body")
struct CreateNote {
    @Param("Note title") var title: String
    @Param("Markdown body") var body: String
    @Param("Pin to top") var pinned: Bool = false

    func perform() async throws -> String {
        try await NoteStore.shared.create(title: title, body: body, pinned: pinned)
    }
}
```

The `@AgentTool` macro generates at compile time:

- `AgentToolProtocol` conformance with a full `MCPToolDescriptor`
- An `asAgentTool()` factory for server registration
- JSON Schema derived from `@Param` types and descriptions
- Type-safe argument dispatch via memberwise initialization

The library also ships adapter modules that export the same tool descriptors into OpenAI, Anthropic, and Apple Foundation Models formats, plus an MCP-compliant HTTP transport so external agents can connect over the wire.

On the consumption side, the library provides a Swift-native MCP client. iOS apps can connect to any MCP server (Notion, Linear, home automation, custom internal tools) and surface discovered tools through native LLM-SDK adapters. Your app becomes both a tool provider and a tool consumer in the broader MCP ecosystem.

## What This Project Is Not

- **Not a production-ready SDK.** This is research code exploring a design space. The API will change. Do not ship it in an App Store app today.
- **Not an LLM.** SwiftAgent does not include a language model. It provides the tool surface that LLMs consume. You bring your own model (llama.cpp, OpenAI API, Anthropic API, Apple Foundation Models).
- **Not a replacement for AppIntents.** SwiftAgent builds on top of Apple's AppIntent framework, not alongside it. The macro generates AppIntent conformances. If you only need Siri and Shortcuts, use AppIntents directly.
- **Not a full MCP implementation.** The library implements the tools subset of the Model Context Protocol (initialize, tools/list, tools/call). Resources, prompts, sampling, and elicitation are declared in the type system but not implemented in the server.
- **Not cross-platform.** SwiftAgent is Apple-only by design. It depends on Foundation, Network.framework, NaturalLanguage, SwiftData, and AppIntents. If you need cross-platform MCP, use the official TypeScript or Python SDKs.

## Why We Are Exploring This

Three trends converging:

1. **LLM tool calling is becoming universal.** Every major model provider (OpenAI, Anthropic, Google, Apple) now supports function/tool calling. The Model Context Protocol is emerging as the interoperability standard. But each provider defines tools in a slightly different JSON format, and none of them provide a Swift-native authoring experience.

2. **Apple is investing heavily in on-device AI.** Foundation Models framework (iOS 18.1+), Apple Intelligence, enhanced Siri with multi-app intent chaining. All of these consume AppIntents as their tool vocabulary. But AppIntents is its own declaration format that does not interoperate with MCP or cloud LLM SDKs without manual bridging.

3. **iOS apps are becoming agent hosts.** Apps are shipping built-in AI assistants, chat interfaces, and automated workflows. Each one needs to declare tools for its LLM, manage argument schemas, validate inputs, dispatch calls, and render results. This is boilerplate that a framework should handle.

SwiftAgent explores whether a single macro-based declaration can unify all three. The research question is: can we make tool adoption so cheap that every iOS app ships a rich tool surface without thinking about it?

## Architecture and Approach

The library has two sides:

**Authoring (outbound).** You declare tools using `@AgentTool` and `@Param`. The macro generates protocol conformances and schema metadata. The server module hosts these tools and makes them callable via transports (in-process for same-app agents, HTTP for external agents, TCP+Bonjour for LAN discovery). Adapter modules export the same descriptors into OpenAI, Anthropic, and Foundation Models formats.

**Consumption (inbound).** The client module connects to any MCP server over HTTP and fetches its tool catalog. Adapter modules translate discovered tools into native LLM-SDK formats so your app's AI features can call external tools without writing transport code or parsing JSON-RPC.

The two sides share a common type system (`MCPToolDescriptor`, `MCPSchema`, `JSONValue`, `MCPCallToolResult`) so tools flow in both directions through the same infrastructure.

## Package Structure

```
SwiftAgent/
  Sources/
    SwiftAgentCore/           Wire-format types: JSON-RPC, MCP messages, schema, errors
    SwiftAgentServer/         Tool DSL, server actor, tool registry, transports
    SwiftAgentClient/         Client actor, discovery (NWBrowser), transports
    SwiftAgentIntents/        AppIntent bridge (one-line intent-to-tool registration)
    SwiftAgentMacros/         @AgentTool and @Param compiler plugin
    SwiftAgent/               Umbrella module (re-exports + macro declarations)
    SwiftAgentOpenAI/         Tool descriptor to OpenAI functions format
    SwiftAgentAnthropic/      Tool descriptor to Anthropic tool_use format
    SwiftAgentFoundationModels/ Apple on-device LLM adapter (gated on availability)
    SwiftAgentHTTPServer/     MCP streamable HTTP server transport
    SwiftAgentHTTPClient/     MCP streamable HTTP client transport
    MCPTestServer/            Executable: minimal MCP server for testing
    AgentRunner/              Executable: agentic CLI wiring LLM to MCP tools
  Tests/
    SwiftAgentCoreTests/      Wire format, schema, end-to-end, adapter tests
    SwiftAgentMacroTests/     Macro expansion verification
  Demos/
    SwiftAgentNotes/          iOS notes app with AI chat, vectors, note linking
    SwiftAgentTasks/          iOS task manager with remote MCP consumption
  docs/
    reframe-story.md          How the project pivoted from AppMCP to SwiftAgent
    phase-3-build.md          Building the macro, transports, and adapters
    phase-4-on-device.md      On-device testing and the six deployment bugs
    phase-5-agentic-loop.md   LLM integration, vectors, note linking
```

## How It All Works Together

The system has four components that run independently and communicate over HTTP:

```
[llama.cpp server]          Runs the LLM (Qwen3.5-9B). Port 8080.
        |
        | HTTP (OpenAI-compatible /v1/chat/completions)
        |
[AgentRunner CLI]           Sends prompts + tool catalog to LLM.
   or [Notes app]           When LLM returns tool_calls, dispatches them
        |                   to the MCP server. Sends results back to LLM.
        |
        | HTTP (MCP JSON-RPC at /mcp)
        |
[MCPTestServer]             Hosts tools (echo, add, current_time, greet,
                            machine_info). Port 9090.
```

The Notes app also has its own local tools (create_note, list_notes, etc.) hosted via an in-process transport. These do not go over the network. The app merges local and remote tools into one catalog and passes all of them to the LLM. The LLM picks which tool to call. SwiftAgent routes the call to the right transport automatically.

**Why are the servers separate?** Because they do different things. The LLM server runs a language model and speaks the OpenAI chat completions API. The MCP server hosts callable tools and speaks the MCP JSON-RPC protocol. Keeping them separate means you can swap either independently: use a different model, point at a different tool server, add more tool servers, or replace the MCP server with a production backend. The architecture is the same one you would use in production, not a monolith you would have to decompose later.

## Getting Started

### Requirements

- macOS 14+ (Sonoma) for building the library and running servers
- Xcode 16+ (for Swift macros via swift-syntax 600+)
- iOS 17+ device or simulator for the demo apps
- XcodeGen (`brew install xcodegen`) for generating demo app Xcode projects
- llama.cpp with a GGUF model for LLM testing (optional but recommended)

### Build the library

```bash
cd ~/Desktop/SwiftAgent
swift build
```

### Run the tests

```bash
swift test
```

This runs 43 tests covering JSON-RPC encoding, schema validation, end-to-end server/client loops, macro expansion, and adapter output.

## Building the Demo Apps

Both demo apps use XcodeGen to generate Xcode projects from a `project.yml` file.

### SwiftAgent Notes

```bash
cd ~/Desktop/SwiftAgent/Demos/SwiftAgentNotes
xcodegen generate
open SwiftAgentNotes.xcodeproj
```

In Xcode, select your iPhone (device or simulator), set a development team under Signing & Capabilities, and build.

Features: 10 `@AgentTool` tools (CRUD, semantic search, similarity, linking), AI chat powered by llama.cpp, Apple NaturalLanguage embeddings for on-device semantic vectors, bidirectional note linking with similarity suggestions.

### SwiftAgent Tasks

```bash
cd ~/Desktop/SwiftAgent/Demos/SwiftAgentTasks
xcodegen generate
open SwiftAgentTasks.xcodeproj
```

Features: 7 `@AgentTool` tools (task CRUD, projects, completion), remote MCP server connection via Settings, local + remote tool sections in the Agent panel.

### First build takes time

The first build downloads and compiles `swift-syntax` (the macro dependency). This can take 5 to 10 minutes. Subsequent builds are fast.

## Running the MCP Test Server

The MCPTestServer is a minimal MCP server that exposes five tools for testing connectivity and tool dispatch.

```bash
cd ~/Desktop/SwiftAgent
swift run MCPTestServer
```

Output:

```
MCP Test Server running
  URL: http://localhost:9090/mcp
  Tools: echo, add, current_time, greet, machine_info
```

The server runs on port 9090 and accepts MCP JSON-RPC requests over HTTP. It stays up until you press Ctrl+C.

To connect from an iPhone app, use your Mac's local IP instead of localhost:

```bash
ipconfig getifaddr en0
# Example: 10.0.0.72
```

Then in the app's Settings view, enter: `http://10.0.0.72:9090/mcp`

Both devices must be on the same Wi-Fi network.

## Running the LLM Server (llama.cpp)

SwiftAgent does not include a language model. For the agentic loop (LLM decides which tools to call), you need llama.cpp running with a tool-calling-capable model.

### Setup

If you already have llama.cpp installed:

```bash
llama-server \
  --model /path/to/your-model.gguf \
  --port 8080 \
  --host 0.0.0.0 \
  --chat-template chatml
```

The server exposes an OpenAI-compatible API at `http://127.0.0.1:8080/v1/chat/completions`.

### Connecting from the Notes app

In the Notes app Settings view, set the LLM URL to:

```
http://10.0.0.72:8080/v1/chat/completions
```

(Replace with your Mac's actual IP.)

Then open the AI Chat (sparkles icon) and type a message. The app sends it to the LLM with the full tool catalog. The LLM decides what to do.

## Running the Agent Runner CLI

The AgentRunner is a terminal-based agentic loop that connects to both llama.cpp and the MCPTestServer. It is useful for testing the tool-calling flow without building an iOS app.

```bash
# Terminal 1: MCP server
swift run MCPTestServer

# Terminal 2: Agent runner (llama.cpp must be running on :8080)
swift run AgentRunner
```

You can override the URLs with environment variables:

```bash
LLM_URL=http://localhost:8080/v1/chat/completions \
MCP_URL=http://localhost:9090/mcp \
swift run AgentRunner
```

Type a message, watch the LLM call tools, see the response with a signature:

```
You: What time is it?
  > calling current_time... done
Assistant: The current time is 2026-04-16T05:30:00Z.
--- Performed by qwen3.5 using current_time in 2.34s ---
```

## Why Are the Servers Separate?

The LLM server and the MCP tool server are separate processes because they solve different problems and scale differently.

**The LLM server** loads a multi-gigabyte model into GPU memory and runs neural network inference. It speaks the OpenAI chat completions API. You choose the model, the quantization, the context length, and the hardware. In production, this might be a cloud API (OpenAI, Anthropic) instead of a local llama.cpp instance.

**The MCP tool server** hosts callable functions with typed schemas. It speaks the MCP JSON-RPC protocol. Each tool is a thin wrapper around your app's business logic. In production, this is your backend, your database, your internal APIs.

**The agent (AgentRunner or the Notes app)** sits between them. It sends the user's prompt plus the tool catalog to the LLM, receives tool-call decisions, dispatches them to the MCP server, feeds results back to the LLM, and renders the final response.

This separation means:

- Swap the model without touching your tools
- Swap the tools without touching your model
- Run multiple tool servers and merge their catalogs
- Test tools without an LLM (use the manual Agent panel)
- Test the LLM without tools (use a plain chat prompt)
- Deploy each component independently

## Test Model

We test with **Qwen3.5-9B** (GGUF quantization) running on llama.cpp with Metal GPU acceleration on an M4 Pro MacBook Pro (24GB unified RAM). The model uses approximately 9.8GB of device memory, leaving 8GB free.

Qwen3.5 was chosen because:

- It supports OpenAI-compatible tool calling natively
- The 9B parameter size fits comfortably on Apple Silicon with room for the MCP server and Xcode
- It runs at reasonable speed for interactive tool-calling loops (2 to 5 seconds per round trip)
- It is open-weight and freely available

Any model that supports OpenAI-compatible function calling will work. The library does not depend on Qwen specifically.

## Testing and Verification

### Automated tests

```bash
swift test
```

43 tests covering:

- JSONValue round-trip fidelity across all seven JSON types
- JSON-RPC envelope encoding, decoding, and error codes
- MCPSchema validation (required fields, bounds, enums, nested arrays)
- End-to-end server/client loops through in-process transport
- Macro expansion verification for @AgentTool and @Param
- OpenAI and Anthropic adapter output structure

### Manual verification

To verify the full stack end-to-end on a real device:

1. Start the MCPTestServer on your Mac
2. Launch the Notes app on your iPhone
3. Connect to the MCP server via Settings
4. Open the Agent panel, select `machine_info`, tap Invoke
5. You should see your Mac's hostname and OS version

This proves the HTTP transport, JSON-RPC protocol, MCP handshake, tool dispatch, and result rendering all work across a real network.

### Verifying the agentic loop

1. Start llama.cpp with Qwen3.5-9B on your Mac
2. Start the MCPTestServer on your Mac
3. In the Notes app Settings, set both the LLM URL and MCP URL
4. Open AI Chat, type: "What machine is the server running on?"
5. Watch: Qwen calls `machine_info`, gets your Mac's hostname, responds naturally
6. The signature shows the model name, tool used, and round-trip duration

## Troubleshooting

### "Address already in use" when starting MCPTestServer

A previous instance is still running. Kill it:

```bash
lsof -ti:9090 | xargs kill -9 2>/dev/null
swift run MCPTestServer
```

### "Local network prohibited" from the iPhone

iOS needs explicit permission for local network access. Check:

1. iPhone Settings > Privacy & Security > Local Network > find your app > toggle ON
2. The app's Info.plist must contain `NSLocalNetworkUsageDescription` and `NSBonjourServices`
3. The app's Info.plist must contain `NSAppTransportSecurity` with `NSAllowsLocalNetworking` set to `true`

### "The Internet connection appears to be offline" from the iPhone

This usually means App Transport Security is blocking plain HTTP. Add to Info.plist:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>
```

### "Server has already been initialized"

The MCP server used to reject reconnections. This has been fixed. If you see this on an older build, pull the latest code and rebuild.

### localhost does not work from a real iPhone

On a real device, `localhost` refers to the iPhone itself, not your Mac. Use your Mac's LAN IP:

```bash
ipconfig getifaddr en0
```

The iOS simulator shares the Mac's network stack, so localhost works there.

### XcodeGen overwrites Info.plist

If `xcodegen generate` strips your custom Info.plist keys, set these in `project.yml`:

```yaml
settings:
  base:
    INFOPLIST_FILE: Sources/Info.plist
    GENERATE_INFOPLIST_FILE: false
```

### First build is very slow

The first build compiles `swift-syntax` from source. This is a one-time cost of 5 to 10 minutes. Subsequent builds are fast.

### Useful commands

```bash
# Find your Mac's local IP
ipconfig getifaddr en0

# Kill a process holding a port
lsof -ti:8080 | xargs kill -9 2>/dev/null

# Check what is listening on a port
lsof -i :9090

# Build a specific target
swift build --target MCPTestServer

# Run tests for a specific test class
swift test --filter SwiftAgentMacroTests

# Clean build artifacts
swift package clean
```

## How This Scales

The architecture is designed so that each layer scales independently:

**More tools.** Add a new `@AgentTool` struct and register it. The macro handles schema generation and dispatch. The LLM sees it automatically in the next tool catalog fetch.

**More apps.** Each app declares its own tools via `@AgentTool` and registers them with its own `AgentServer`. Multiple apps can expose tools simultaneously over different ports or Bonjour services.

**More models.** The OpenAI-compatible adapter works with any model that supports function calling: GPT-4, Claude, Gemini, Llama, Qwen, Mistral, Phi. Swap the model URL and the same tools work.

**More MCP servers.** The client module supports connecting to multiple MCP servers simultaneously. The Notes app already demonstrates this: local tools via in-process transport plus remote tools via HTTP, merged into one catalog.

**Production deployment.** The MCP server component is a standard HTTP server. Deploy it behind a reverse proxy, add authentication, and it becomes a production tool API. The library's `HTTPServerTransport` is the development path; production would use a proper HTTP framework (Vapor, Hummingbird) with the same `AgentServer` actor behind it.

## What This Works With

| Component | What we tested | What else should work |
|---|---|---|
| LLM | Qwen3.5-9B via llama.cpp | Any OpenAI-compatible API (GPT-4, Claude via proxy, Gemini, Ollama, LM Studio, vLLM) |
| MCP server | Our MCPTestServer | Any MCP-compliant server (official SDK servers, Claude Desktop MCP servers) |
| iOS device | iPhone on iOS 17+ | iPad, Mac Catalyst, visionOS (all supported in Package.swift) |
| Embedding | Apple NLEmbedding (English) | Other NLEmbedding languages, custom embedding models via llama.cpp /v1/embeddings |
| Transport | HTTP, in-process, TCP+Bonjour | Any custom transport conforming to `AgentServerTransport` or `AgentClientTransport` |

## Blog Posts / Build Journal

The `docs/` directory contains narrative blog posts documenting the design decisions, pivots, bugs, and lessons learned during development. Read them in order:

1. **[reframe-story.md](docs/reframe-story.md)** How we started building an MCP framework, realized a consuming app would not need it, and pivoted to a unified tool-declaration SDK.

2. **[phase-3-build.md](docs/phase-3-build.md)** Building the @AgentTool macro, the HTTP transports, and the LLM-SDK adapters. Three bugs found and fixed by audit.

3. **[phase-4-on-device.md](docs/phase-4-on-device.md)** What happened when the code ran on a real iPhone for the first time. Six deployment bugs invisible to swift test.

4. **[phase-5-agentic-loop.md](docs/phase-5-agentic-loop.md)** Connecting Qwen3.5-9B to the tool surface, adding Apple NaturalLanguage embeddings, and building bidirectional note linking.

## Contributing

This is a research project and contributions are welcome. If you are interested in:

- Adding support for another LLM provider (Gemini, Cohere, etc.)
- Implementing MCP resources, prompts, or sampling
- Building adapters for other agent frameworks (LangChain, CrewAI, AutoGen)
- Improving the macro to generate AppIntent conformances automatically
- Adding tests for the HTTP transport layer
- Building more demo apps that showcase the tool surface

Please open an issue to discuss your idea before submitting a pull request. The API is still evolving and coordination helps avoid wasted work.

### Code conventions

- One type per file
- Full doc comments on every public type, property, and method
- Strict concurrency (`Sendable`, actor isolation, `@unchecked Sendable` only with documented thread safety)
- No external dependencies beyond `apple/swift-syntax` (for the macro target)
- Tests for every new feature

## License

This project is released for research and educational purposes. See `LICENSE` for details.
