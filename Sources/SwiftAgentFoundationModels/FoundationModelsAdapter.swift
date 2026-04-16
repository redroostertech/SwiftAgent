import Foundation
import SwiftAgentCore
import SwiftAgentServer

/// Adapter that bridges SwiftAgent tool descriptors into Apple's
/// Foundation Models `Tool` protocol for on-device LLM inference.
///
/// Gated behind `#if canImport(FoundationModels)` because the
/// framework is only available on iOS 26+ / macOS 26+. When not
/// available, this file compiles to an empty stub so the target
/// still resolves.
///
/// Implementation deferred pending Foundation Models API stabilization.
/// The adapter will wrap `MCPToolDescriptor` + handler pairs into
/// `Tool`-conforming values that Apple's on-device model can call.
#if canImport(FoundationModels)
import FoundationModels

// Deferred: Foundation Models `Tool` protocol bridge. Will read
// MCPToolDescriptor schemas, map them to Tool parameter declarations,
// and route perform() calls through AgentServer's handler dispatch.
// Blocked on Foundation Models API surface stabilizing (iOS 26+).

#endif

/// Placeholder so the target compiles on platforms where
/// Foundation Models is not available.
public enum FoundationModelsAdapterStatus {
    /// Whether the Foundation Models framework is available on this
    /// platform at runtime.
    public static var isAvailable: Bool {
        #if canImport(FoundationModels)
        return true
        #else
        return false
        #endif
    }
}
