# Closing the Loop: LLM + Tools + Vectors

*The session where a notes app on an iPhone started talking to a
language model on a Mac, and the model started making its own
decisions.*

---

## Where we were

Phase 4 ended with a working demo: an iPhone app that could invoke
MCP tools on a Mac server over HTTP, and a Mac-side AgentRunner CLI
that wired Qwen3.5-9B to those tools. But the two halves were
separate. The iPhone app had a manual tool picker — the user chose
which tool to call and filled in the arguments by hand. The LLM was
in a terminal on the Mac.

The user asked the obvious question: *shouldn't I be able to trigger
some action from the notes app to connect to Qwen?*

Yes. That's the whole point.

---

## The AI Chat view

We added a chat interface to the Notes app — a `sparkles` button in
the toolbar that opens a conversation view. Type a natural language
message. The app sends it to Qwen3.5-9B (running on the Mac via
llama.cpp) along with the full tool catalog in OpenAI function-calling
format. Qwen decides whether to call a tool, which one, and with
what arguments. SwiftAgent dispatches the call — either locally via
the in-process transport or remotely via HTTP — and sends the result
back to Qwen. Qwen synthesizes a natural-language response.

The user sees: a chat bubble with their question, a brief "Calling
create_note_tool..." status line, and then the assistant's answer
with a signature at the bottom:

```
Performed by qwen3.5 using create_note_tool in 3.2s
```

The signature stamps every response with which model made the
decision, which tools it chose, and the total round-trip time.

### The architecture

```
iPhone (Notes app)
  → User types: "Create a note about grocery shopping"
  → NoteAgentManager.chat() sends to Qwen via HTTP POST
  → Qwen responds with tool_calls: [create_note_tool(title: "Grocery Shopping", ...)]
  → Manager dispatches via AgentClient.callTool()
  → Tool handler runs, writes to SwiftData, returns note ID
  → Manager sends tool result back to Qwen
  → Qwen responds: "I've created a note titled Grocery Shopping for you."
  → Chat bubble renders with signature
  → Note appears in the sidebar
```

No human in the tool-calling loop. The model reasons, the framework
dispatches, the data mutates, the UI updates.

### Settings

The LLM URL is configurable alongside the MCP server URL. Both live
in the Settings view:

- **LLM Server**: `http://10.0.0.72:8080/v1/chat/completions`
  (your Mac's IP where llama.cpp runs)
- **MCP Server**: `http://10.0.0.72:9090/mcp` (the MCPTestServer
  with echo, add, current_time, greet, machine_info)

The app can invoke local tools (its own note tools via in-process
transport) and remote tools (from the MCP server via HTTP)
simultaneously. Qwen sees all of them in one merged catalog and
chooses freely.

---

## Vectors and note linking

While wiring the LLM, we realized the notes app was missing the
intelligence that would make it more than a CRUD demo. Two features
landed in the same session:

### Semantic embeddings

Every note now has an embedding vector computed on-device using
Apple's NaturalLanguage framework (`NLEmbedding.sentenceEmbedding`).
When you create or update a note, the framework embeds the combined
title + body into a 512-dimensional dense vector.

This enables **semantic search** — "find notes about food" matches a
note titled "Grocery List" even though the words don't overlap. It
also enables **similarity discovery** — open any note and see which
other notes are semantically related, ranked by cosine similarity
with percentage scores.

The embedding computation is entirely on-device. No network call, no
API key, no privacy trade-off. Apple ships the English sentence
embedding model bundled with iOS.

For existing notes created before the embedding feature, the app
runs `backfillEmbeddings()` on launch — a one-time migration that
computes vectors for every note that doesn't have one.

### Note linking

Notes can be explicitly linked to each other. Links are bidirectional
— if note A links to note B, note B also links to note A. Links are
stored as an array of note IDs on each note.

In the editor, linked notes appear in a "Linked Notes" section.
Below that, a "Similar Notes" section shows the top 5 semantically
related notes computed from embeddings. Each similar note has a link
button — tap it to promote the suggestion into an explicit link.

### New tools

Four new `@AgentTool` declarations (10 total now):

- `semantic_search_notes_tool` — searches by meaning using embeddings;
  falls back to text search if embeddings aren't available
- `find_similar_notes_tool` — finds notes similar to a given note by
  cosine similarity on their embedding vectors
- `link_notes_tool` — creates a bidirectional link between two notes
- `get_linked_notes_tool` — lists all notes linked to a given note

With Qwen in the loop, the conversation becomes:

```
You: "Create a note about grocery shopping"
Qwen: → create_note_tool → "Created."

You: "Create a note about meal planning for the week"
Qwen: → create_note_tool → "Created."

You: "What notes are similar to the grocery one?"
Qwen: → find_similar_notes_tool → "Meal Planning (87% similar)"

You: "Link those two together"
Qwen: → link_notes_tool → "Linked."
```

The model makes the semantic connection, calls the right tools in
sequence, and the note graph grows.

---

## The MCPTestServer additions

We also added a `machine_info` tool to the test server that returns
the Mac's hostname, OS version, and process ID. When invoked from the
iPhone, this is unambiguous proof that the response crossed the
network — the iPhone cannot produce the Mac's hostname.

This was the moment the SDK's cross-device story became real instead
of theoretical. You point your phone at a server, the server runs on
your Mac, and the tools work.

---

## AgentRunner: the CLI proof

Before the Notes app got its AI chat, we built `AgentRunner` — a
command-line tool that connects to both llama.cpp and an MCP server,
runs the same agentic loop, and prints responses with the same
signature stamp.

```bash
swift run MCPTestServer    # Terminal 1
swift run AgentRunner      # Terminal 2

You: What time is it?
  → calling current_time... ✓
Assistant: It's currently 2026-04-16T05:30:00Z.
─── Performed by qwen3.5 using current_time in 2.34s ───
```

The AgentRunner and the Notes app's AI chat run the same loop with
the same tool catalog. One is a terminal, the other is a phone.
The framework doesn't care.

---

## Bugs along the way

Every one of these was a deployment bug invisible to `swift test`:

- **Port collision**: llama.cpp and MCPTestServer both defaulted to
  8080. Moved MCPTestServer to 9090.
- **`Duration` overflow**: `Task.sleep(for: .seconds(.greatestFiniteMagnitude))`
  crashes. Replaced with a never-resuming continuation.
- **`localhost` from iPhone**: on a real device, localhost is the
  phone. Use the Mac's LAN IP.
- **SSE content negotiation**: client asked for SSE, server sent it,
  parser failed. Fixed by requesting JSON only.
- **`NSAppTransportSecurity`**: iOS blocks plain HTTP to local IPs.
  Added `NSAllowsLocalNetworking`.
- **`MCPError` / `JSONRPCError` opacity**: both showed "error N"
  instead of actual messages. Fixed with `LocalizedError` conformance.
- **`alreadyInitialized`**: server rejected reconnects. Fixed to
  allow re-initialization.
- **XcodeGen plist overwrite**: XcodeGen regenerated Info.plist and
  stripped the network permission keys. Fixed with
  `GENERATE_INFOPLIST_FILE: false`.

---

## What we have now

The Notes app is no longer a demo. It's a functional, intelligent
notes application with:

- 10 `@AgentTool` tools — CRUD, semantic search, similarity, linking
- Apple NaturalLanguage embeddings — on-device, no API key
- Bidirectional note linking with similarity-based suggestions
- AI Chat powered by Qwen3.5-9B — the LLM decides which tools to call
- Local + remote tool catalog — your tools and any MCP server's tools
  in one unified surface
- Signature stamps on every response — model, tools, duration

All of it built on SwiftAgent. One `@AgentTool` annotation per tool.
The rest is framework.

---

## What this means for SwiftAgent

The session proved the full thesis:

1. **Authoring works**: `@AgentTool` declarations generate protocol
   conformances, MCP descriptors, and typed dispatch from one annotated
   struct.
2. **Transport works**: in-process for local tools, HTTP for remote
   tools, both transparently routed by the same client.
3. **LLM integration works**: OpenAI-compatible tool calling via
   `SwiftAgentOpenAI.export()` — the LLM sees the tools, calls them,
   gets results, responds.
4. **On-device AI works**: Apple's NLEmbedding powers semantic search
   without leaving the phone.
5. **Cross-device works**: iPhone → Mac over HTTP, tools dispatched
   and results returned, verified with hostname proof.

The next step is either shipping the Tasks app with the same AI
capabilities, or starting to think about what a v0.1 open-source
release of SwiftAgent looks like.
