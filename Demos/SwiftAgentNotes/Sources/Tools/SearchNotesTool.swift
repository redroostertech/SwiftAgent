import Foundation
import SwiftAgent

/// Agent tool that performs full-text search across note titles and bodies.
///
/// Returns matching notes with their ID, title, and a pinned indicator.
@AgentTool("Search notes by title or body content")
struct SearchNotesTool {
    @Param("Search query string") var query: String

    func perform() async throws -> String {
        let notes = try await NoteStore.shared.search(query: query)
        let lines = notes.map { note in
            let pin = note.pinned ? " [pinned]" : ""
            return "\(note.id) | \(note.title)\(pin)"
        }
        if lines.isEmpty { return "No notes matched the query." }
        return lines.joined(separator: "\n")
    }
}
