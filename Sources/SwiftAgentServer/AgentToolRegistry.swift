import Foundation
import SwiftAgentCore

/// The tool catalog owned by an ``AgentServer``.
///
/// `AgentToolRegistry` is a small, actor-hosted store that maps a tool
/// name to its runnable ``AppMCPTool``. It enforces uniqueness on
/// registration, provides O(1) lookup on dispatch, and exposes an
/// ordered snapshot suitable for `tools/list` responses — the order
/// matches registration order so clients see a deterministic catalog.
///
/// The registry is not a public API on its own; callers interact with it
/// through ``AgentServer``. It lives in its own type so that it can be
/// unit-tested in isolation and so the server actor stays focused on
/// session lifecycle.
public struct AgentToolRegistry: Sendable {
    private var tools: [String: AppMCPTool] = [:]
    private var order: [String] = []

    /// Build an empty registry.
    public init() {}

    /// Register a tool by its name. Throws if a tool with the same name
    /// is already present — duplicate registration is always a bug, so
    /// the caller sees it loudly instead of silently masking the older
    /// definition.
    ///
    /// - Parameter tool: The tool to register.
    /// - Throws: ``MCPError/custom(code:message:data:)`` when a duplicate
    ///   name is detected.
    public mutating func register(_ tool: AppMCPTool) throws {
        if tools[tool.name] != nil {
            throw MCPError.custom(
                code: -32050,
                message: "Duplicate tool registration: \(tool.name)"
            )
        }
        tools[tool.name] = tool
        order.append(tool.name)
    }

    /// Replace any previously registered tool with the given name,
    /// inserting it if it did not exist. Unlike ``register(_:)`` this
    /// never throws — intended for hot reloads.
    public mutating func replace(_ tool: AppMCPTool) {
        if tools[tool.name] == nil {
            order.append(tool.name)
        }
        tools[tool.name] = tool
    }

    /// Unregister a tool by name. No-op if the name is unknown.
    public mutating func unregister(_ name: String) {
        if tools.removeValue(forKey: name) != nil {
            order.removeAll { $0 == name }
        }
    }

    /// Look up a tool by name.
    public func tool(named name: String) -> AppMCPTool? {
        tools[name]
    }

    /// The list of registered tool descriptors in registration order.
    /// Used to answer `tools/list` requests.
    public var descriptors: [MCPToolDescriptor] {
        order.compactMap { tools[$0]?.descriptor }
    }

    /// The full list of registered runnable tools in registration order.
    public var allTools: [AppMCPTool] {
        order.compactMap { tools[$0] }
    }

    /// `true` if no tools are registered.
    public var isEmpty: Bool { tools.isEmpty }

    /// Number of tools currently registered.
    public var count: Int { tools.count }
}
