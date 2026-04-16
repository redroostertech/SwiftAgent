import Foundation
import SwiftAgent

/// Agent tool that fetches the full content of a single note by ID.
///
/// Returns the note's title, body, pinned state, and timestamps.
@AgentTool("Get the full content of a note by its ID")
struct GetNoteTool {
    @Param("Note ID") var id: String

    func perform() async throws -> String {
        guard let note = try await NoteStore.shared.get(id: id) else {
            return "Note not found: \(id)"
        }
        let created = ISO8601DateFormatter().string(from: note.createdAt)
        let updated = ISO8601DateFormatter().string(from: note.updatedAt)
        return """
        Title: \(note.title)
        Pinned: \(note.pinned)
        Created: \(created)
        Updated: \(updated)
        ---
        \(note.body)
        """
    }
}
