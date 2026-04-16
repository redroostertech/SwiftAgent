import Foundation

/// Result builder that powers the declarative parameter list inside an
/// ``AppMCPTool`` definition.
///
/// It lets you write:
///
/// ```swift
/// AppMCPTool(name: "create_note", description: "...") {
///     .string("title", description: "Note title")
///     .string("body", description: "Markdown body")
///     .boolean("pinned", description: "Pin to top", isRequired: false)
/// } handler: { args in
///     ...
/// }
/// ```
///
/// Supports `if`/`else`, `for ... in`, and optional parameters via `if let`,
/// matching the shape of every other Swift result builder. Produces an
/// ordered `[AppMCPParameter]` — order is preserved so that deterministic
/// UIs can render parameters in the order the developer declared them.
@resultBuilder
public enum AgentParameterBuilder {
    /// Combine a variadic list of parameters into a single array. This is
    /// the common path — most call sites hit this overload.
    public static func buildBlock(_ components: AppMCPParameter...) -> [AppMCPParameter] {
        components
    }

    /// Combine arrays from nested statements (for example inside `for` loops).
    public static func buildBlock(_ components: [AppMCPParameter]...) -> [AppMCPParameter] {
        components.flatMap { $0 }
    }

    /// Lift a single parameter into a one-element array for use inside
    /// `if` statements.
    public static func buildExpression(_ expression: AppMCPParameter) -> [AppMCPParameter] {
        [expression]
    }

    /// Pass an already-assembled array through unchanged.
    public static func buildExpression(_ expression: [AppMCPParameter]) -> [AppMCPParameter] {
        expression
    }

    /// Handle `if` statements without an `else` branch — the unconditional
    /// path produces the components, a missing branch produces an empty list.
    public static func buildOptional(_ component: [AppMCPParameter]?) -> [AppMCPParameter] {
        component ?? []
    }

    /// Handle `if` statements with an `else` branch (true case).
    public static func buildEither(first component: [AppMCPParameter]) -> [AppMCPParameter] {
        component
    }

    /// Handle `if` statements with an `else` branch (false case).
    public static func buildEither(second component: [AppMCPParameter]) -> [AppMCPParameter] {
        component
    }

    /// Handle `for ... in` loops by flattening the per-iteration arrays.
    public static func buildArray(_ components: [[AppMCPParameter]]) -> [AppMCPParameter] {
        components.flatMap { $0 }
    }

    /// Handle `if #available` and similar compile-time conditional blocks.
    public static func buildLimitedAvailability(_ component: [AppMCPParameter]) -> [AppMCPParameter] {
        component
    }
}
