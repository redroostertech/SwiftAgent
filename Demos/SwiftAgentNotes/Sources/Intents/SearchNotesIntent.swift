import AppIntents
import Foundation

/// Siri/Shortcuts intent for searching notes.
///
/// Invokable via:
///   "Search notes for [query] in SwiftAgent Notes"
///   "Find notes about [query]"
struct SearchNotesIntent: AppIntent {
    static var title: LocalizedStringResource = "Search Notes"

    static var description = IntentDescription(
        "Search your notes by keyword or meaning."
    )

    @Parameter(title: "Query", description: "What to search for")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Search notes for \(\.$query)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let results = try await NoteStore.shared.semanticSearch(query: query, limit: 5)
        if results.isEmpty {
            return .result(value: "No notes found matching '\(query)'.")
        }
        let lines = results.map { item in
            let score = String(format: "%.0f%%", item.similarity * 100)
            return "- \(item.note.title) (\(score) match)"
        }
        return .result(value: "Found:\n" + lines.joined(separator: "\n"))
    }
}
