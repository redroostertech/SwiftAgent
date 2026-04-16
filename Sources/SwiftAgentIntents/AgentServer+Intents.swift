import Foundation
import SwiftAgentCore
import SwiftAgentServer

#if canImport(AppIntents)
import AppIntents

@available(iOS 16.0, macOS 13.0, macCatalyst 16.0, tvOS 16.0, visionOS 1.0, watchOS 9.0, *)
public extension AgentServer {
    /// Register an `AppIntent`-based tool on the server.
    ///
    /// This is the one-liner consuming apps use to expose a Siri /
    /// Shortcuts intent through SwiftAgent. The framework builds an
    /// ``AgentTool`` whose descriptor is derived from the intent's
    /// ``AgentExposableIntent`` metadata and whose handler forwards
    /// into ``AgentExposableIntent/mcpPerform(_:)``.
    ///
    /// - Parameter intentType: The intent type to expose.
    /// - Throws: ``MCPError`` on duplicate registration.
    ///
    /// ### Example
    ///
    /// ```swift
    /// try await AgentServer.shared.register(intent: CreateNoteIntent.self)
    /// ```
    func register<I: AgentExposableIntent>(intent intentType: I.Type) throws {
        let tool = AgentTool(
            name: I.mcpName,
            title: I.mcpTitle,
            description: I.mcpDescription,
            annotations: I.mcpAnnotations,
            parameters: { I.mcpParameters },
            handler: { args in
                try await I.mcpPerform(args)
            }
        )
        try self.register(tool)
    }
}

#endif
