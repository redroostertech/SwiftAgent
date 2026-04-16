import Foundation

/// Naming helpers for AppMCP-exposed intents.
///
/// Intent type names follow Swift's `PascalCase` convention
/// (`CreateNoteIntent`), while MCP tool names on the wire follow a
/// `lower_snake_case` convention (`create_note_intent`) for
/// compatibility with the rest of the MCP ecosystem. This enum owns
/// the one-way conversion between the two, and is also used by
/// ``AgentExposableIntent/mcpName`` to derive a sensible default.
public enum AgentIntentNaming {
    /// Convert a `PascalCase` or `camelCase` identifier into
    /// `lower_snake_case` suitable for an MCP tool name.
    ///
    /// - "CreateNoteIntent" → "create_note_intent"
    /// - "fetchURL" → "fetch_url"
    /// - "HTTPRequestIntent" → "http_request_intent"
    ///
    /// Acronyms are kept as runs (`"HTTPRequest"` → `"http_request"`,
    /// not `"h_t_t_p_request"`) because the alternative is painful to
    /// read.
    ///
    /// - Parameter name: The type name to convert.
    /// - Returns: The snake-cased form.
    public static func snakeCase(_ name: String) -> String {
        guard !name.isEmpty else { return name }
        var output: [Character] = []
        output.reserveCapacity(name.count + 4)

        let characters = Array(name)
        for index in characters.indices {
            let current = characters[index]
            if current.isUppercase {
                let previous = index > 0 ? characters[index - 1] : nil
                let next = index + 1 < characters.count ? characters[index + 1] : nil

                let previousIsLower = previous?.isLowercase ?? false
                let previousIsUpper = previous?.isUppercase ?? false
                let nextIsLower = next?.isLowercase ?? false

                let needsSeparator =
                    (previousIsLower) ||
                    (previousIsUpper && nextIsLower)

                if needsSeparator && !output.isEmpty {
                    output.append("_")
                }
                output.append(Character(current.lowercased()))
            } else {
                output.append(current)
            }
        }
        return String(output)
    }

    /// Build a default MCP tool name for a given intent type. Uses
    /// Swift's runtime `String(describing:)` on the metatype and then
    /// ``snakeCase(_:)`` to produce a DNS-friendly name.
    ///
    /// - Parameter type: The intent type.
    /// - Returns: The default MCP tool name.
    public static func defaultMCPName(for type: Any.Type) -> String {
        snakeCase(String(describing: type))
    }
}
