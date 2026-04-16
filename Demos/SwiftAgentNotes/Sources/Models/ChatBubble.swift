import Foundation

/// A single message bubble displayed in the AI chat view.
///
/// Each bubble has a role (user, assistant, tool status, or system info),
/// the displayed text, and an optional signature line that shows which
/// LLM model performed the action, which tools it called, and how long
/// the round trip took.
struct ChatBubble: Identifiable {
    /// Stable identifier for SwiftUI list diffing.
    let id = UUID()

    /// Who produced this message.
    let role: ChatRole

    /// The displayed text content.
    let text: String

    /// Optional signature line shown below assistant responses, e.g.
    /// "Performed by qwen3.5 using create_note_tool in 2.3s".
    var signature: String?

    /// The role of a chat participant.
    enum ChatRole {
        /// A message from the user.
        case user
        /// A response from the LLM assistant.
        case assistant
        /// A status line showing a tool being called.
        case tool
        /// A system-level informational message.
        case system
    }
}
