# From "iOS MCP Framework" to "Codable for LLM Tools": A Reframe Story

*How we set out to build one thing, got honest about what doesn't work,
and landed on something better.*

---

## The original ask

The goal was simple enough to fit on a napkin: **build an open-source
Swift framework that lets iOS apps expose their functionality to other
apps via the Model Context Protocol (MCP).**

The timing felt perfect. The tool-calling ecosystem is consolidating
around MCP — every serious LLM client speaks it, every agent framework
emits it, every IDE assistant consumes it. But on Apple platforms
there's no native Swift adoption story. Apps on iPhone, iPad, Mac,
Watch, and Vision Pro live on an island. Meanwhile Apple is heading
toward a future where on-device LLMs consume tool-shaped capabilities:
Foundation Models framework (iOS 18.1+), Apple Intelligence, Siri's
new multi-app chaining. The intersection felt obvious.

We started writing code.

---

## The first honest reckoning: iOS says no

A few hours into the build — the wire types were compiling, the
declarative tool DSL was taking shape — we stopped to ask the only
question that matters on iOS: **does the sandbox actually allow any of
this?**

The answer was a rolling series of nos:

- **iOS suspends backgrounded apps aggressively.** An MCP server
  implemented as an `NWListener` dies within ~30 seconds of leaving the
  foreground. You cannot run a persistent listener on iOS the way you
  can on macOS or Linux.
- **Only one app is foregrounded at a time** (except iPad Split View
  or Stage Manager). An "agent" app calling tools in three other apps
  simultaneously is physically impossible on iPhone.
- **Local network access triggers a system permission dialog.** The
  first time Bonjour or any LAN-bound traffic fires, iOS shows a
  "would like to find devices on your local network" prompt. Users
  will decline it. Every consuming app inherits this UX tax.
- **There is no public API for one third-party app to invoke another
  third-party app's functions.** No XPC, no shared memory, no
  cross-vendor App Groups. Apple deliberately prevents this.

Every primitive that makes MCP work on a desktop OS doesn't exist on
iOS. The naive design — "run an MCP server in your iOS app, let
external agents connect" — was dead on arrival.

We documented the constraints, noted where the design was still valid
(macOS, where apps run as real long-lived processes), and started
looking for what iOS *does* allow.

---

## The App Intents pivot

iOS has exactly one sanctioned mechanism for apps to expose callable
functions to external processes: **App Intents.**

A declared `AppIntent` lights up an extraordinary number of system
surfaces for free:

1. Siri (voice invocation, even from the background)
2. Shortcuts (user-built or system-suggested workflows)
3. Spotlight (inline actions in search)
4. Home Screen widgets (tap-to-invoke)
5. Control Center controls (iOS 18+)
6. Lock Screen controls
7. Action Button / Apple Watch complications
8. Interactive notifications
9. Focus Filters
10. Apple Intelligence — Siri's LLM can now compose multi-step
    workflows across apps using declared intents as tools

And the critical one: **background execution.** When an intent is
invoked by the system, Apple extends the target app's process briefly
to run `perform()`, even if the app was backgrounded or cold-launched.
This is the thing iOS does not offer through any other third-party
mechanism.

The reframe felt clean: build AppMCP as a thin layer over App Intents.
Declare a tool once, conform it to an `AppMCPExposableIntent` protocol,
and the framework would expose it as an MCP tool through an in-process
transport while also letting every AppIntent surface use it. "No risk,
all reward" was the pitch to consuming apps — no new permissions, no
new entitlements, no sockets, no background work, no review risk.

We built it. Four targets (`AppMCPCore`, `AppMCPServer`, `AppMCPClient`,
`AppMCPIntents`), 43 source files, 32 passing tests. The core shipped a
full JSON-RPC 2.0 layer, typed MCP protocol messages, a JSON Schema
validator, a declarative tool DSL with a result builder, server and
client actors, in-process and network transports, and an AppIntent
bridge that was a single protocol conformance. It compiled. It passed
tests. We were proud of the engineering.

Then we tried to plan demo apps and everything started to slip.

---

## The demo planning moment

The original macOS-era demo plan called for five apps running
simultaneously: two apps demonstrating tool calling between an
inspector and a notes server, and three apps demonstrating multi-app
orchestration between a tasks app, a calendar app, and an orchestrator
agent.

When we mapped the plan onto iOS, every piece broke:

- Multi-app orchestration requires multiple apps foregrounded at once.
  iOS only supports this via iPad Split View (2 apps) or Stage Manager
  (a few more, awkwardly).
- "Inspector discovers all AppMCP servers on the device" is impossible
  because iOS offers no public API to enumerate other apps'
  capabilities at runtime.
- Even for a simple 2-app iPad Split View demo, the backgrounded app
  would die the moment the user switched focus, taking its tool server
  with it.

Every demo we sketched looked like a reduced, apologetic version of
the macOS one. We scoped down from 5 apps to 4. Then 3. Then 2. We
started hedging language in the plan itself: "foreground-only on iOS,"
"iPad Stage Manager recommended," "works best on macOS." The plan was
full of footnotes. That should have been the signal.

---

## "Is this really MCP?"

The first hard question came when we stepped back from the demos and
looked at the library itself.

Our core spoke JSON-RPC 2.0 and used MCP's method names (`tools/list`,
`tools/call`, `initialize`) and message shapes. But it shipped a
**custom Bonjour+TCP transport** that no reference MCP client knows how
to speak. It had a content-type extension (`MCPContent.json`) that
isn't in the spec. It implemented tools but not resources, prompts,
sampling, or elicitation. A vanilla Claude Desktop could not connect to
it.

Verdict: MCP-shaped. Not MCP-compatible on the wire.

The fix seemed straightforward — add the official HTTP+SSE transport,
align protocol versions, drop extensions, pass a conformance test
against the official MCP reference SDK. A day or two of work.

But that fix exposed the second, much harder question.

---

## "Does a consuming app even need our SDK?"

Walk the path of a hypothetical iOS developer in 2026 asking "should I
add this dependency?"

- **"I want Siri integration."** → Write an `AppIntent`. Done. No
  AppMCP.
- **"I want Shortcuts."** → Add `AppShortcutsProvider`. Done. No
  AppMCP.
- **"I want widgets, Control Center, Lock Screen actions."** →
  WidgetKit + AppIntent. Done. No AppMCP.
- **"I want Apple Intelligence to chain my tools."** → Declare
  AppIntents with good descriptions. The system does the rest. No
  AppMCP.
- **"My in-app LLM uses Apple's Foundation Models."** → The `Tool`
  protocol works with AppIntents directly. Apple ships this natively.
  No AppMCP.
- **"My in-app LLM uses OpenAI's SDK."** → Write tool definitions in
  OpenAI's JSON format. No AppMCP.
- **"I want an external Mac agent to reach into my iOS app."** →
  AppMCP could provide this while the iOS app is foregrounded, but
  "while foregrounded" is an edge case, not a product.

Every individual use case had a shipping solution that wasn't our
library. What we'd built was a well-engineered, well-tested protocol
layer that duplicated capabilities the platform already provided. The
one place it was genuinely unique — cross-app LAN tool calling — was
gated by iOS's foreground-only limitation.

If we shipped the library as-is, the honest answer to "does a
consuming app need this?" was: **no, not really.**

That's the kind of realization that kills a project. We almost let it.

---

## The pain nobody else has solved

We sat with the question instead of dismissing it, and asked a
different version: **what actually hurts that nobody on Apple platforms
has fixed?**

The answer was tool declaration fragmentation.

A serious iOS app in 2026 that ships AI features ends up maintaining
the *same tool* in four to seven different formats:

| Surface | Format |
|---|---|
| Siri / Shortcuts / widgets / Apple Intelligence | `AppIntent` with `@Parameter` wrappers |
| On-device LLM (Foundation Models) | `Tool` protocol |
| Cloud LLM via OpenAI SDK | JSON schema in OpenAI `functions` format |
| Cloud LLM via Anthropic SDK | Anthropic `InputSchema` format |
| Cloud LLM via Vercel AI, LangChain, etc. | Yet another shape |
| External MCP clients (Claude Desktop, Cursor) | MCP tool descriptor |
| In-app agent loop | Hand-rolled |

All of these declarations describe the same function. They get out of
sync. Adding a parameter means updating it in six places. Arguments
are re-validated six times. Tests are duplicated across formats.
Nobody's mental model is the source of truth.

Nothing on Apple platforms solves this. Apple is happy if you use
AppIntents exclusively, but most apps won't — they talk to cloud LLMs,
they want MCP compatibility, they have their own agent loops. The LLM
SDK vendors don't solve it either; OpenAI, Anthropic, and Vercel each
define their own format and don't talk to each other. The MCP
reference implementations are Node and Python, not Swift.

There is a genuine, unsolved, painful problem here. And it has a clean
solution.

---

## The reframe: Codable for LLM tools

The analogy that made everything click was `Codable`.

In Swift you don't write JSON encoders by hand. You mark a type
`Codable` and the compiler generates the encoding/decoding for every
format you need — JSON, property lists, custom codecs. You write the
struct *once* and the serialization falls out.

Our library should do the same thing for agent tools. You declare a
tool *once* with a Swift macro:

```swift
@Tool("Create a note with a title and body")
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

The macro expands at compile time into every downstream format:

- A full `AppIntent` with `AppShortcutsProvider` → Siri, Shortcuts,
  widgets, Apple Intelligence, Spotlight, Control Center, Lock Screen
- An Apple Foundation Models `Tool` conformance → on-device LLM
- OpenAI `function` and Anthropic `tool` JSON → cloud LLM SDKs
- An MCP `MCPToolDescriptor` → external agents over the wire
- A registered in-process tool → your own agent loop

One declaration, six output formats, zero hand-maintained duplicates.
The fragmentation problem is solved at the source.

---

## The other half we weren't talking about: inbound tools

All the discussion up to that point had been about *authoring* —
your app declares tools, others consume them. But serious AI apps also
**consume** tools. Your iOS writing assistant wants to query the user's
Notion vault. Your iOS dashboard wants to invoke the user's home
automation. Your iOS coding helper wants to read the user's local
filesystem.

iOS has no good story for being an MCP client. The reference MCP SDKs
are all server-side Node and Python. Implementing a Swift MCP client
from scratch means: HTTP+SSE transport, JSON-RPC framing, session
management, tool discovery, translating discovered tools into whatever
LLM SDK your app uses. That's a substantial project per MCP backend.

The reframed library handles this side too. It ships a Swift-native
MCP client that connects to any MCP server and surfaces discovered
tools through native LLM-SDK adapters:

```swift
let vault = try await Client.connect(to: userNotionURL)
let remoteTools = try await vault.listTools()
    .map { $0.asFoundationModelsTool() }

let response = try await llm.respond(
    to: prompt,
    tools: localTools + remoteTools
)
```

This is "mobile-first AI tooling" landing concretely. Your iOS app
becomes a first-class participant in the MCP ecosystem — and unlike
the server side, the client side has **no foreground-only limitation.**
You're the one making the HTTP call; iOS doesn't care.

---

## What changes for the project

### New identity

The library is no longer "MCP for Apple apps." It's a **Swift-native,
mobile-first agent-tool SDK for Apple platforms, with MCP as its
interoperability layer.** MCP is one feature — the bridge to the
broader ecosystem — not the brand. The name will change to reflect
this (we're evaluating candidates; see `NAMING.md`).

### New primary surface: the macro

Today's library asks developers to write boilerplate. The reframed
library asks for one struct with a `@Tool(...)` attribute and compiles
everything from there. Without the macro, the library is "another MCP
impl." With it, adoption collapses to a few lines per tool and the
"every surface from one declaration" pitch is real.

### New targets

Beyond the existing protocol core, the reframed library adds:
- A macro target (swift-syntax, codegen of AppIntent + adapters)
- LLM-SDK adapter targets (Foundation Models, OpenAI, Anthropic)
- A spec-compliant MCP HTTP client (for the consumption side)
- A spec-compliant MCP HTTP server (for the authoring side, where
  transport allows)
- A conformance test suite against the official MCP reference SDK

### New demos

The previous demos were trying to prove "MCP works on iOS" by
mirroring a macOS design that iOS can't host. The new demos prove the
actual value prop: one declaration → every surface → plus the MCP
ecosystem access from the client side. Two iOS apps, each a credible
v0.1 of a commercial product, each showing the full multi-surface
story from a handful of macro-annotated structs.

---

## The lesson

When you catch yourself apologizing in every paragraph of a plan, the
plan is wrong.

The first version of the demo plan had footnotes on every page:
foreground-only, permission-gated, 2-apps-max on iPad, honestly
limited. Every caveat was true. But the cumulative effect was a library
scoping itself down to justify its own existence. If your demo plan
spends more words on what doesn't work than on what does, the problem
isn't the demo — it's the library.

The fix wasn't scoping further. It was stepping back and asking whether
the library solved a real problem *at all.* The answer was almost-no —
until we reframed what it was for, and then it became an unambiguous
yes. A problem nobody on Apple platforms had solved, with a clean
approach and a forward-compatible architecture that played *with*
Apple's direction rather than against it.

Every line of protocol code from the first three days still applies.
The JSON-RPC types, the tool descriptors, the schema validator, the
DSL, the transports — all kept. The protocol layer was never the
mistake. The mistake was calling it the product.

The product is the macro, the adapters, the bidirectional MCP bridge,
and the mobile-first identity. The protocol is the plumbing.

---

## What's next

We're renaming the project, building the macro, adding the LLM-SDK
adapter targets, implementing the inbound MCP client, and closing the
remaining MCP spec gaps in the outbound server. The iOS demo apps will
showcase the new positioning: one tool declaration that lights up
Siri, Shortcuts, widgets, Apple Intelligence, an in-app LLM agent,
and the user's MCP ecosystem — all from a single annotated struct.

We're shipping the story of how we got here alongside the code, so
other people building tool SDKs on Apple platforms don't spend three
days building the wrong thing before they find the right one.

We almost did.
