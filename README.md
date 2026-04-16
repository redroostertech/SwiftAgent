# SwiftAgent

A Swift-native, mobile-first agent-tool SDK for Apple platforms, with
MCP as its interoperability layer.

**One tool declaration. Every integration surface. Zero duplication.**

Declare a tool once with a Swift macro. The library compiles it at
build time into: an AppIntent (Siri, Shortcuts, widgets, Apple
Intelligence), a Foundation Models Tool (on-device LLM), OpenAI and
Anthropic function schemas (cloud LLMs), an MCP tool descriptor
(external agent clients), and an in-process callable (your own agent
loop). One struct, six output formats, no hand-maintained parallel
definitions.

On the consumption side, the library ships a Swift-native MCP client
so iOS apps can connect to any MCP server — local or remote — and
surface discovered tools through native LLM-SDK adapters. Your app
becomes a first-class participant in the broader MCP ecosystem without
writing transport code.

## Status

This project is in the reframe stage. The original implementation
(under `~/Desktop/AppMCP/`) ships a solid MCP-shaped protocol core, a
declarative tool DSL, server/client actors, in-process and network
transports, and an AppIntent bridge. All of that code carries forward
into the reframed library.

What's being added:
- A Swift macro that generates all output formats from one declaration
- LLM-SDK adapter targets (Foundation Models, OpenAI, Anthropic)
- MCP-spec-compliant HTTP transport (for real interop with Claude
  Desktop, Cursor, and the broader MCP ecosystem)
- Conformance tests against the official MCP reference SDK

See `docs/reframe-story.md` for the full narrative of how we got here.
