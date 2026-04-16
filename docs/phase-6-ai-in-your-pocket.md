# AI in Your Pocket: When the Chat Created the Note

*The moment the phone stopped being a viewer and started being a
participant.*

---

## The message that changed things

We had spent hours building infrastructure. Protocol types, macro
codegen, HTTP transports, MCP servers, test harnesses, deployment
bugs, Info.plist keys. Necessary work, but abstract. The library
compiled. The tests passed. The server responded with the right
JSON. All correct, none of it visceral.

Then we opened the AI Chat on the iPhone, typed "Create a note
about grocery shopping," and watched a note appear in the sidebar.

Not because we tapped a plus button. Not because we filled in a
form. Because a language model running on a MacBook four feet away
read the sentence, decided on its own to call `create_note_tool`,
chose the title and body, and SwiftAgent dispatched it through the
in-process transport into SwiftData. The note materialized in the
UI the same way it would have if a human had created it manually,
because it went through the same code path. The model did not get a
special API. It used the same `@AgentTool` struct that Siri would
use, that Shortcuts would use, that any MCP client would use.

One declaration. The model found it, called it, and the data changed.

That was the moment the project stopped being a protocol library and
started being something that mattered.

---

## What we built in this session

### AI Chat in the Notes app

A `sparkles` button in the toolbar opens a chat interface. You type
natural language. The app sends your message to Qwen3.5-9B (running
via llama.cpp on the Mac) along with the full tool catalog in
OpenAI function-calling format. Qwen reasons about what to do. If
it decides to call a tool, SwiftAgent dispatches the call, either
locally (in-process transport for note tools) or remotely (HTTP
transport for MCP server tools). The result goes back to Qwen.
Qwen synthesizes a response. The response appears as a chat bubble
with a signature line at the bottom:

```
Performed by qwen3.5 using create_note_tool in 3.2s
```

The signature is not decoration. It is accountability. Every
response stamps which model made the decision, which tools it
chose, and how long the round trip took. When something goes wrong,
you know exactly where to look.

### The agentic loop

The chat is not a single-turn request/response. It is a loop. Qwen
can chain multiple tool calls in sequence. Ask "Create a note about
groceries and then find similar notes" and Qwen will call
`create_note_tool`, read the result, then call
`find_similar_notes_tool` with the new note's ID, and synthesize a
response that references both results. Up to five iterations of
tool calling per turn, configurable.

The app does not know in advance which tools the model will call or
in what order. It sends the catalog, the model decides, the
framework dispatches. This is the difference between a tool browser
(the manual Agent panel, where a human picks the tool) and an agent
(the AI Chat, where the model picks the tool). Both use the same
infrastructure. The model just removes the human from the
selection loop.

### Semantic vectors with Apple NaturalLanguage

Every note now carries a semantic embedding vector computed
on-device using Apple's NaturalLanguage framework. When you create
or update a note, the framework passes the title and body through
`NLEmbedding.sentenceEmbedding` and stores the resulting
512-dimensional vector alongside the note in SwiftData.

This powers two features:

**Semantic search.** The `semantic_search_notes_tool` embeds the
query string and finds notes by cosine similarity against their
stored vectors. "Find notes about food" matches a note titled
"Grocery List" even though the words do not overlap. The text-based
`search_notes_tool` still exists for exact matches. The model
chooses which one to use based on the query.

**Similarity discovery.** The `find_similar_notes_tool` takes a
note ID, retrieves its embedding, and ranks all other notes by
cosine similarity. Open any note in the editor and a "Similar
Notes" section shows the top five matches with percentage scores,
computed entirely on-device with no network call.

The embedding model ships bundled with iOS. No API key, no data
leaving the device, no privacy trade-off. Apple does the heavy
lifting. SwiftAgent just stores the vectors and runs the math.

### Bidirectional note linking

Notes can now be linked to each other explicitly. Links are
bidirectional: linking note A to note B also links B to A. The
editor shows a "Linked Notes" section listing all connected notes,
and below it a "Similar Notes" section where each suggested note
has a link button. Tap it to promote a semantic suggestion into a
permanent connection.

Two new tools support this from the LLM side:

- `link_notes_tool` creates a bidirectional link given two note IDs
- `get_linked_notes_tool` lists all notes linked to a given note

So the conversation can flow naturally:

```
You: Create a note about grocery shopping
Qwen: [calls create_note_tool] Created.

You: Create a note about meal planning
Qwen: [calls create_note_tool] Created.

You: Are any of my notes related to each other?
Qwen: [calls find_similar_notes_tool] Grocery Shopping and
      Meal Planning are 87% similar.

You: Link them
Qwen: [calls link_notes_tool] Linked.
```

The model discovered the semantic relationship, surfaced it, and
acted on it. The human just said "link them." The note graph grew
by one edge.

### Markdown preview

The note editor gained an Edit/Preview toggle. Tap the eye icon to
render the note body as formatted markdown (bold, italic, links,
lists, code spans). Tap the pencil icon to return to the raw text
editor. The preview uses SwiftUI's `AttributedString(markdown:)`
parser, which handles CommonMark inline syntax.

This pairs well with the AI chat. Ask Qwen to "Create a note with
a markdown checklist for a road trip" and the generated note renders
with proper checkboxes and formatting in preview mode. The model
writes markdown because the tool description says "Markdown body."
The editor renders it because SwiftUI can parse it. No special
integration needed.

---

## Settings: two URLs, two worlds

The Settings view now has two configurable URLs:

**LLM Server.** The OpenAI-compatible endpoint where Qwen runs.
On our test setup this is `http://10.0.0.72:8080/v1/chat/completions`,
pointing at llama.cpp on the Mac. Any model that supports function
calling works here: swap in GPT-4, Claude (via a proxy), Ollama,
LM Studio, or vLLM by changing the URL.

**MCP Server.** The tool server endpoint. On our test setup this is
`http://10.0.0.72:9090/mcp`, pointing at the MCPTestServer with
echo, add, current_time, greet, and machine_info. In production
this would be your backend's tool surface.

The app merges tools from both sources (local note tools via
in-process transport, remote tools from the MCP server via HTTP)
into a single catalog. The LLM sees all of them. It does not know
or care which transport a tool uses. That routing is SwiftAgent's
job.

---

## Small things that matter

### Keyboard dismissal

Every text field in the app now has `.submitLabel(.done)` or
`.submitLabel(.send)`. The return key is labeled appropriately and
tapping it dismisses the keyboard. In the AI Chat, tapping send
clears the input and drops the keyboard immediately so you can
watch the response stream in without the keyboard blocking the
view.

Small, but the kind of thing that makes a research prototype feel
like an app instead of a demo.

### The "machine_info" proof

We added a tool to the MCPTestServer called `machine_info` that
returns the hostname, OS version, and process ID of the Mac running
the server. When you invoke it from the iPhone, the response
contains information the phone cannot produce. It is unambiguous
proof that the data crossed the network.

We used this to verify that the agentic loop was real, not local.
The phone talks to Qwen on the Mac. Qwen decides to call a tool.
The tool runs on the Mac. The result comes back to the phone. The
phone shows you your Mac's hostname. That is a four-hop round trip
across two HTTP connections (phone to LLM, phone to MCP server),
verified by content that could only originate at the server.

---

## The ten tools

The Notes app now exposes ten `@AgentTool` declarations:

| Tool | What it does | Annotation |
|---|---|---|
| `create_note_tool` | Create a note with title, body, pinned flag | |
| `list_notes_tool` | List all notes with optional limit | read-only |
| `search_notes_tool` | Text search across title and body | read-only |
| `semantic_search_notes_tool` | Embedding-based search by meaning | read-only |
| `get_note_tool` | Fetch full note content by ID | read-only |
| `update_note_tool` | Update title, body, or pinned by ID | |
| `delete_note_tool` | Delete a note by ID | destructive |
| `find_similar_notes_tool` | Find semantically similar notes | read-only |
| `link_notes_tool` | Bidirectional link between two notes | |
| `get_linked_notes_tool` | List all notes linked to a given note | read-only |

Each one is a single annotated struct. The macro generates the
protocol conformance, the JSON Schema, the argument dispatch, and
the registration factory. Ten tools, ten structs, zero boilerplate.

---

## What we learned

**The LLM does not need to be on the phone.** Running Qwen on the
Mac and calling it over HTTP from the iPhone works well for
development and for power-user workflows where a desktop machine
is nearby. The latency is 2 to 5 seconds per round trip, which is
acceptable for tool-calling use cases (you are waiting for the
model to think, not streaming tokens). When Apple's Foundation
Models framework matures, the same tool declarations will work with
an on-device model through the Foundation Models adapter target,
with no code changes.

**The tool catalog is the API.** The LLM does not know anything
about SwiftData, SwiftUI, NLEmbedding, or the note editor. It
knows the tool catalog: ten functions with typed parameters and
natural-language descriptions. That is the entire contract. As long
as the tools do what their descriptions say, the model makes good
decisions. When a description is vague, the model makes bad ones.
The quality of the agentic experience is determined by the quality
of the tool descriptions, not the complexity of the infrastructure.

**Embeddings make the graph emerge.** Before vectors, notes were
isolated documents. After vectors, every note has a position in
semantic space. Similar notes cluster. The model can discover
relationships the user did not explicitly create. Adding a link
button to the similarity suggestions turns passive discovery into
active graph construction. The note graph grows through use, not
through manual curation.

**The framework disappears.** By the end of this session, nobody
was thinking about JSON-RPC, MCP handshakes, transport protocols,
or macro expansion. The conversation was about notes, similarity
scores, markdown rendering, and keyboard behavior. The framework
had become invisible. That is the goal. The best infrastructure is
the kind you stop noticing.

---

## What is next

The Notes app is now a functional, intelligent, agent-powered notes
application. The Tasks app has the same MCP connectivity but not yet
the AI chat or vectors. Bringing those features to Tasks would prove
the pattern is repeatable.

Beyond that, the open questions are:

- Can the `@AgentTool` macro generate full `AppIntent` conformances
  so Siri and Shortcuts work from the same declaration?
- What does a production HTTP transport look like (Vapor/Hummingbird
  behind the `AgentServer` actor)?
- Can we run the embedding model through llama.cpp's `/v1/embeddings`
  endpoint for richer vectors than NLEmbedding provides?
- What happens when you point two apps' tool catalogs at the same
  LLM and let it orchestrate across both?

The infrastructure is ready. The tools are declared. The model is
listening. The interesting part is what you build on top.
