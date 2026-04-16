import Foundation
import SwiftAgent

/// Agent tool that finds notes semantically similar to a given note.
///
/// Uses Apple's NaturalLanguage embedding vectors to compute cosine
/// similarity between notes. Returns the most similar notes ranked
/// by relevance score.
@AgentTool("Find notes semantically similar to a given note")
struct FindSimilarNotesTool {
    @Param("ID of the note to find similar notes for") var id: String
    @Param("Maximum number of similar notes to return") var limit: Int = 5

    func perform() async throws -> String {
        let results = try await NoteStore.shared.findSimilar(
            toNoteID: id, limit: Int(limit)
        )
        if results.isEmpty {
            return "No similar notes found."
        }
        let lines = results.map { item in
            let score = String(format: "%.0f%%", item.similarity * 100)
            return "[\(score)] \(item.note.title) (id: \(item.note.id))"
        }
        return lines.joined(separator: "\n")
    }
}
