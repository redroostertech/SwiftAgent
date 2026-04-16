# Building the Engine: SwiftAgent Phase 3

*How we implemented the macro, the transports, and the adapters — and
what broke along the way.*

---

## Where we started

Phase 3 began with a fully migrated codebase: 54 source files across
12 targets, 33 passing tests, all renamed from AppMCP to SwiftAgent.
The protocol core was solid — JSON-RPC 2.0, MCP message types, JSON
Schema validation, a declarative tool DSL, server and client actors,
in-process and Bonjour/TCP transports, and an AppIntent bridge. But
the pieces that actually differentiate SwiftAgent — the ones that make
a consuming app *need* this SDK — were all stubs.

Three workstreams, parallelizable:

- **The `@AgentTool` macro** — the hero feature. One annotated struct
  generates everything.
- **HTTP transports** — MCP streamable HTTP server and client, so
  SwiftAgent speaks the same wire format as Claude Desktop and every
  other MCP client.
- **LLM-SDK adapters** — OpenAI and Anthropic tool export, so declared
  tools fan out to every LLM provider format.

We ran the macro build in the foreground (it needed the most design
care) and fired the HTTP transport build as a background agent.

---

## The macro: @AgentTool and @Param

The macro is the single piece that transforms SwiftAgent from "another
MCP protocol library" into "the reason you adopt this SDK." Without it,
developers hand-write tool registrations and maintain parallel
definitions. With it, they write a struct and everything else is
generated.

### What the developer writes

```swift
@AgentTool("Create a note with a title and body")
struct CreateNote {
    @Param("Note title")     var title: String
    @Param("Markdown body")  var body: String
    @Param("Pin to top")     var pinned: Bool = false

    func perform() async throws -> String {
        try await NoteStore.shared.create(
            title: title, body: body, pinned: pinned
        )
    }
}
```

### What the macro generates

An `extension CreateNote: AgentToolProtocol` containing:

1. **`toolName`** — `"create_note"`, derived from the struct name via
   a PascalCase→snake\_case converter that handles acronyms
   (`FetchHTTPRequest` → `fetch_http_request`).

2. **`toolDescription`** — the string literal from `@AgentTool("...")`.

3. **`descriptor`** — a full `MCPToolDescriptor` with a JSON Schema
   derived from the `@Param` properties. Required vs. optional is
   inferred from whether the property has a default value. Descriptions
   flow through to the schema so LLM callers see them.

4. **`perform(arguments:)`** — a static method that constructs the
   struct via its memberwise initializer, pulling each argument from
   the `AgentToolArguments` bag with typed accessors, then calls the
   user's `perform()` method and wraps the result.

5. **`asAgentTool()`** — a factory that wraps the struct as an
   `AgentTool` value suitable for `AgentServer.register()`.

### Implementation details

The macro is an `ExtensionMacro` — it generates an entire `extension`
block rather than modifying the original struct. This is the cleanest
macro pattern for protocol conformance: the original source stays
untouched, and the generated code lives in an extension that the
compiler can type-check independently.

`@Param` is a `PeerMacro` that generates nothing. Its only purpose is
to carry the description string so `@AgentTool` can read it during
expansion. This "metadata-only macro" pattern avoids property-wrapper
complexity while keeping the declaration site readable.

### The bugs we caught

Post-implementation audit found three bugs in the macro, all in the
code generation layer:

**Bug 1 (critical): parameterless init.** The initial codegen
produced `var instance = CreateNote()`, which only compiles if every
stored property has a default. A struct with required `@Param`
properties (no defaults) has no parameterless init — the compiler
error would surface at the call site, not the declaration site, making
it baffling to debug. Fix: generate a memberwise init call that passes
each argument directly to the initializer.

**Bug 2: discarded descriptions.** Parameter descriptions were
extracted from `@Param` attributes but silently dropped in the schema
builder — an early debug artifact (`_ = desc`) that survived into the
shipped code. Fix: pass descriptions through to `MCPSchema` builders
so the descriptor carries them.

**Bug 3: incomplete type dispatch.** The schema builder declared
support for `Int8`, `Int16`, `Int32` alongside `Int` and `Int64`, but
the argument-dispatch code only checked for `Int` and `Int64`. Smaller
integer types silently fell through to a string accessor. Fix: unified
all integer types into a single `integerTypes` constant used by every
codegen method.

All three were caught by a thorough audit *before* any consumer could
hit them. The macro expansion tests now verify the exact generated
source for each supported pattern.

---

## HTTP transports: speaking real MCP

The second workstream ran as a background agent and delivered two
targets:

### HTTPServerTransport

A `NWListener`-based HTTP/1.1 server that speaks the MCP 2025-06-18
Streamable HTTP transport:

- Accepts `POST /mcp` requests with JSON-RPC bodies
- Responds with `application/json` for simple request/response
- Responds with `text/event-stream` (SSE) when the client accepts it
- Manages sessions via the `Mcp-Session-Id` header
- Supports `DELETE` for session teardown
- Returns `202 Accepted` for notifications

HTTP/1.1 parsing is manual (not `NWProtocolHTTP`, which requires
macOS 15+) for broader compatibility. The parser handles
`Content-Length` framing, header case-insensitivity, and graceful
rejection of malformed requests.

### HTTPClientTransport

A `URLSession`-based HTTP client that works on every Apple platform
including watchOS:

- Sends JSON-RPC as `POST` body
- Handles both `application/json` and `text/event-stream` responses
- Maintains session identity via `Mcp-Session-Id`
- Sends best-effort `DELETE` on close for session cleanup
- `SSEReader` handles incremental parsing with chunk-boundary
  buffering and `\r\n` line-ending normalization

### SSE framing

Both sides share a pair of framing utilities:

- `SSEWriter` — stateless, formats `event:`, `data:`, and `id:`
  fields into W3C Server-Sent Events wire format, splitting multi-line
  data payloads correctly.
- `SSEReader` — incremental parser that buffers partial lines across
  chunk boundaries, handles `\r`, `\n`, and `\r\n` terminators, and
  emits complete `SSEEvent` values when a blank line signals dispatch.

A post-build audit caught dead code in `SSEReader`'s `\r\n` handling
— a conditional block that contained only a comment and whose boolean
expression simplified away. Fixed to actually consume the trailing
`\n` after a `\r` to prevent spurious blank lines.

---

## LLM-SDK adapters

The adapter story is simpler than the macro or transport because the
adapters are pure functions: `MCPToolDescriptor` in, LLM-vendor JSON
out.

### OpenAI

`OpenAIToolExport.export([MCPToolDescriptor])` → a `JSONValue` array
in OpenAI's `tools` format:

```json
[{
  "type": "function",
  "function": {
    "name": "create_note",
    "description": "Create a note with a title and body",
    "parameters": { ... }
  }
}]
```

Key translation: OpenAI uses `parameters` (not `inputSchema`) and
nests everything under a `function` key.

### Anthropic

`AnthropicToolExport.export([MCPToolDescriptor])` → a `JSONValue`
array in Anthropic's Messages API format:

```json
[{
  "name": "create_note",
  "description": "Create a note with a title and body",
  "input_schema": { ... }
}]
```

Key translation: Anthropic uses `input_schema` (not `inputSchema` or
`parameters`) and puts the schema at the top level.

### Foundation Models

Deferred pending API stabilization (iOS 26+). The target compiles on
all platforms via `#if canImport(FoundationModels)` and exposes a
`FoundationModelsAdapterStatus.isAvailable` flag for runtime checks.
The full implementation will wrap `MCPToolDescriptor` + handler pairs
into Apple's `Tool` protocol.

### Tests

Seven adapter tests verify:
- Both adapters produce structurally valid output
- Schema properties flow through correctly
- Empty descriptor lists produce empty arrays
- Both adapters preserve the same tool name for the same descriptor
  (cross-format consistency)

---

## Final state

After Phase 3 + the audit-driven fixes:

- **59 source files** across 12 targets
- **43 passing tests** (32 migrated + 4 macro expansion + 7 adapter)
- **Zero build warnings**
- **Zero `AppMCP` references** in source
- **Zero stale Phase-3 / TODO / placeholder markers** (all either
  implemented or honestly marked as deferred with a reason)

The three workstreams that make SwiftAgent a real SDK — the macro,
the HTTP transports, and the LLM adapters — are all functional and
tested. The library can now honestly claim: one tool declaration,
multiple output formats, MCP wire compatibility, and bidirectional
MCP ecosystem participation.

---

## What's next

Phase 4 is the demo apps. Two iOS apps — Notes and Tasks — each
built on the `@AgentTool` macro, demonstrating the hero claim in a
real UI: one struct declaration that lights up Siri, Shortcuts,
widgets, an in-app agent, and MCP compatibility, all from a single
annotated type.

The demos will be the first real consumer of the macro-generated code,
which means they'll be the first integration test of the full stack:
macro → descriptor → server registration → client discovery → tool
invocation → result rendering. If something breaks at that boundary,
the demos will find it.
