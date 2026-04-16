import SwiftSyntax
import SwiftSyntaxMacros

/// The `@Param` macro implementation.
///
/// `@Param` is a peer macro that marks a stored property as a tool
/// parameter and carries its description string. The `@AgentTool` macro
/// reads `@Param` attributes during expansion to discover which
/// properties are parameters and what their descriptions are.
///
/// At the Swift level, `@Param` is inert — it does not modify the
/// property or generate any code on its own. Its purpose is purely to
/// carry metadata that `@AgentTool` consumes.
public struct ParamMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // @Param is metadata-only. The @AgentTool macro reads it during
        // its own expansion. No peer declarations are generated.
        []
    }
}
