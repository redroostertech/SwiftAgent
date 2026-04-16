import Foundation
import SwiftAgent

/// Agent tool that lists all notes with their title, ID, pinned state,
/// and last-updated timestamp.
///
/// Accepts an optional `limit` parameter to cap the number of results.
@AgentTool("List all notes with title, ID, pinned status, and last updated date")
struct ListNotesTool {
    @Param("Maximum number of notes to return") var limit: Int = 0

    func perform() async throws -> String {
        let cap: Int? = limit > 0 ? limit : nil
        let notes = try await NoteStore.shared.list(limit: cap)
        let lines = notes.map { note in
            let pin = note.pinned ? " [pinned]" : ""
            let date = ISO8601DateFormatter().string(from: note.updatedAt)
            return "\(note.id) | \(note.title)\(pin) | \(date)"
        }
        if lines.isEmpty { return "No notes found." }
        return lines.joined(separator: "\n")
    }
}
