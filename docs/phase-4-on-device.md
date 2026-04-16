# On the Device: SwiftAgent Phase 4

*What happened when we stopped running tests and started running the
SDK on a real iPhone talking to a real server.*

---

## The plan

Phase 4 was supposed to be straightforward: build two iOS demo apps
that consume the SwiftAgent SDK, run them, confirm the macro and
transports work end-to-end. Two agents ran in parallel — one building
a notes app, one building a tasks app — each targeting iPhone with
SwiftUI, SwiftData, and the `@AgentTool` macro. XcodeGen for project
generation, local SPM dependency on the SwiftAgent package.

The apps shipped 34 source files across both demos. Every tool was
declared with the `@AgentTool` macro. Both apps had an in-app Agent
panel that auto-generates forms from tool schemas and invokes tools
through the in-process transport. The Tasks app additionally had a
Settings view for connecting to an external MCP server over HTTP.

Then we tried to run them on an actual iPhone, and every assumption
we hadn't tested broke in sequence.

---

## Bug 1: The invisible toolbar button

The Agent panel is accessed through a toolbar button. The button was
attached to the outer `NavigationSplitView`:

```swift
NavigationSplitView {
    NoteListView(selectedNoteID: $selectedNoteID)
} detail: {
    ...
}
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button { ... } label: { Label("Agent", systemImage: "cpu") }
    }
}
```

On iPad this renders fine — the split view has a visible toolbar
region. On iPhone, `NavigationSplitView` collapses into a navigation
stack. The toolbar attached to the *outer* split view doesn't render
in the *inner* navigation bar. The button was invisible.

Fix: move the toolbar into the sidebar content so it lives inside the
navigation bar the user actually sees:

```swift
NavigationSplitView {
    NoteListView(selectedNoteID: $selectedNoteID)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { ... } label: { Label("Agent", systemImage: "cpu") }
            }
        }
} detail: { ... }
```

This is exactly the kind of bug you only find by running on the target
device. The simulator would have caught it too, but we were generating
code from agents — nobody was clicking through the UI until the user
did.

---

## Bug 2: Bool can't sort

SwiftData's `SortDescriptor` requires the key path's value type to
conform to `Comparable`. Notes were sorted pinned-first via:

```swift
@Query(sort: [
    SortDescriptor(\Note.pinned, order: .reverse),
    SortDescriptor(\Note.updatedAt, order: .reverse)
])
```

`Bool` doesn't conform to `Comparable`. This compiled on macOS (the
library's test platform) but failed in the Xcode build targeting iOS.
Fix: sort by `updatedAt` in the query and apply pinned-first ordering
in memory.

Lesson: SwiftData's generic constraints are stricter than they look,
and the compiler doesn't always catch them at the point of the
`@Query` declaration — sometimes the error surfaces deep in generated
code.

---

## Bug 3: Local network prohibited

The first attempt to connect the iPhone to the MCPTestServer on the
Mac failed with:

```
Error Domain=NSURLErrorDomain Code=-1009
"The Internet connection appears to be offline."
UserInfo={ _NSURLErrorNWPathKey=unsatisfied (Local network prohibited) }
```

Two issues stacked:

1. **`NSLocalNetworkUsageDescription` was missing.** XcodeGen's
   `INFOPLIST_KEY_` build-setting approach generated the key for
   simple strings but couldn't produce `NSBonjourServices` as an
   array. We added an explicit `Info.plist` file — then XcodeGen
   overwrote it with its own generated version, stripping the keys.
   Fix: set `GENERATE_INFOPLIST_FILE: false` and `INFOPLIST_FILE:`
   to point at our handwritten plist.

2. **`NSAppTransportSecurity` was missing.** iOS blocks plain HTTP
   (non-HTTPS) to local network addresses by default. Even with the
   local network permission granted, `http://10.0.0.72:8080/mcp`
   fails unless `NSAllowsLocalNetworking` is set to `true` in the
   App Transport Security dictionary.

Both of these are documented in Apple's guides, and both are invisible
until you test on a real device talking to a real server over real
HTTP. Simulators sharing the Mac's network stack don't always enforce
the same transport security policies.

---

## Bug 4: MCPError said nothing useful

When the connection finally went through, the next error was:

```
The operation couldn't be completed.
SwiftAgentCore.MCPError error 4.
```

"Error 4." No message, no context, no clue. The problem: `MCPError`
conformed to `Error` but not `LocalizedError`, so
`error.localizedDescription` used Swift's default formatting, which
shows the type name and the enum case index. Case 4 is
`toolExecutionFailed` — but even knowing that, the associated values
(the tool name, the failure message) were swallowed.

Fix: conform to `LocalizedError` and implement `errorDescription`:

```swift
public enum MCPError: LocalizedError, Sendable, Hashable {
    ...
    public var errorDescription: String? { message }
}
```

One line. The difference between "error 4" and "No valid message event
found in SSE response" — which immediately pointed us to the next bug.

---

## Bug 5: SSE where JSON was expected

The HTTP client was sending:

```
Accept: application/json, text/event-stream
```

The server saw `text/event-stream` in the Accept header and responded
with SSE framing. The client's SSE parser then looked for an event
with type `"message"`, didn't find one (the server was formatting it
differently), and threw the error we could now actually read.

The MCP spec says servers SHOULD respond with `application/json` for
simple request/response exchanges. SSE is for long-lived notification
streams. Our client was asking for both and the server was picking the
wrong one.

Fix: client sends `Accept: application/json` for regular requests.
SSE support will be added when we implement streaming notifications.

---

## Bug 6: Duration overflow

The very first run of MCPTestServer crashed immediately:

```
Fatal error: Double value cannot be converted to _Int128
because it is outside the representable range
```

The server kept itself alive with:

```swift
try await Task.sleep(for: .seconds(Double.greatestFiniteMagnitude))
```

`Double.greatestFiniteMagnitude` overflows `Duration`'s internal
`_Int128` representation. Fix: replace with a never-resuming
`CheckedContinuation` that blocks the main task until Ctrl+C.

(The Swift runtime helpfully warns "leaked its continuation without
resuming it" — which is exactly the behavior we want.)

---

## The proof

After fixing all six bugs, the connection worked. But "it returned the
right string" wasn't enough — how do we know the response actually
crossed the network and wasn't generated locally?

We added a `machine_info` tool to the test server that returns the
Mac's hostname, OS version, and process ID. Information the iPhone
literally cannot produce. When the user invoked it from the Agent
panel on their iPhone and saw their MacBook's hostname staring back
at them, that was the proof.

The full chain, validated on hardware:

```
iPhone app
  → @AgentTool macro-generated tool declarations
  → AgentServer registration
  → AgentClient over InProcessTransport (local tools)
  → AgentClient over HTTPClientTransport (remote tools)
  → HTTP POST to Mac's MCPTestServer
  → AgentServer dispatches tool handler
  → JSON-RPC response over HTTP
  → iPhone renders result in the Agent panel
```

One annotated struct on the server. One `callTool` on the client. The
entire SwiftAgent stack in between, invisible.

---

## What we shipped

**SwiftAgent Notes** (16 files):
- 6 `@AgentTool` tools (create, list, search, get, update, delete)
- SwiftData persistence
- NavigationSplitView with sidebar, editor, search
- Agent panel with local + remote tool sections
- Settings view for MCP server URL connection
- Proper Info.plist with local network and ATS keys

**SwiftAgent Tasks** (19 files):
- 7 `@AgentTool` tools (CRUD + projects + completion)
- Priority dots, due dates, completion checkboxes
- Agent panel with local + remote tool sections
- Settings view with connect/disconnect lifecycle

**MCPTestServer** (1 file):
- 5 tools (echo, add, current_time, greet, machine_info)
- HTTPServerTransport on port 8080
- Runnable via `swift run MCPTestServer`

---

## The lesson, again

Every bug in this phase was a *deployment* bug, not a *logic* bug. The
library's tests all passed. The macro expanded correctly. The JSON-RPC
types round-tripped cleanly. The in-process transport worked. None of
that mattered until the code ran on a real device, talking to a real
server, over a real network, with real iOS security policies in the
way.

Testing on device is not a nice-to-have. It's where you discover that
`Bool` isn't `Comparable`, that `NavigationSplitView` hides your
toolbar, that iOS blocks HTTP to local IPs, that `Duration` can
overflow, that your error type says nothing useful, and that your HTTP
client asks for the wrong content type.

Six bugs. Zero of them showed up in `swift test`. All of them would
have shipped to the first user who tried the SDK in an Xcode project.

---

## What's next

The demo apps prove the SDK works end-to-end on hardware. The
MCPTestServer proves the HTTP wire protocol is real. But the agent
panel is currently a manual tool picker — the user chooses which tool
to invoke and fills in the arguments by hand.

The next step is to close the loop: connect a real LLM (llama.cpp,
already running on this machine) to the SwiftAgent tool surface and
let the model decide which tool to call. That's the full agentic
round trip: user prompt → LLM reasoning → tool selection → SwiftAgent
dispatch → result → LLM response. No human in the tool-calling loop.

That's what makes it an *agent*, not a tool browser.
