import SwiftCompilerPlugin
import SwiftSyntaxMacros

/// Entry point for the SwiftAgent macro compiler plugin.
///
/// Registers the `@AgentTool` and `@Param` macros with the Swift
/// compiler so they are available to any module that imports
/// `SwiftAgent`.
@main
struct SwiftAgentMacroPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [
        // AgentToolMacro.self,
        // ParamMacro.self,
    ]
}
