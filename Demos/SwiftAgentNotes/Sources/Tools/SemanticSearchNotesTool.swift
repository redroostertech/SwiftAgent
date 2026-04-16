import Foundation
import SwiftAgent

/// Agent tool that searches notes using semantic similarity.
///
/// Unlike the text-based ``SearchNotesTool``, this uses Apple's
/// NaturalLanguage embedding vectors to find notes by meaning. A
/// query like "food" will match a note titled "Grocery List" even
/// though the words don't overlap.
@AgentTool("Search notes by semantic meaning using AI embeddings")
struct SemanticSearchNotesTool {
    @Param("What to search for (natural language)") var query: String
    @Param("Maximum number of results") var limit: Int = 5

    func perform() async throws -> String {
        let results = try await NoteStore.shared.semanticSearch(
            query: query, limit: Int(limit)
        )
        if results.isEmpty {
            return "No matching notes found."
        }
        let lines = results.map { item in
            let score = String(format: "%.0f%%", item.similarity * 100)
            return "[\(score)] \(item.note.title) (id: \(item.note.id))"
        }
        return lines.joined(separator: "\n")
    }
}
