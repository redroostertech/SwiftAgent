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
/// Phase 3 implementation — the full version wraps each
/// `MCPToolDescriptor` + handler pair into a `Tool`-conforming
/// value that Apple's on-device model can call natively.
#if canImport(FoundationModels)
import FoundationModels

// Full implementation will go here once Foundation Models API
// surface stabilizes. The adapter reads MCPToolDescriptor schemas,
// maps them to the Tool protocol's parameter declarations, and
// routes perform() calls through the AgentServer's handler dispatch.

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
