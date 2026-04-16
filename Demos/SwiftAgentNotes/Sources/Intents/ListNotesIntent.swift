import AppIntents
import Foundation

/// Siri/Shortcuts intent for listing all notes.
///
/// Invokable via:
///   "Show my notes in SwiftAgent Notes"
///   "List notes"
struct ListNotesIntent: AppIntent {
    static var title: LocalizedStringResource = "List Notes"

    static var description = IntentDescription(
        "List all notes with their titles."
    )

    @Parameter(title: "Limit", description: "Maximum number of notes to show", default: 10)
    var limit: Int

    static var parameterSummary: some ParameterSummary {
        Summary("List up to \(\.$limit) notes")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let notes = try await NoteStore.shared.list(limit: limit)
        if notes.isEmpty {
            return .result(value: "You have no notes yet.")
        }
        let lines = notes.map { note in
            let pin = note.pinned ? " [pinned]" : ""
            return "- \(note.title)\(pin)"
        }
        return .result(value: "Your notes:\n" + lines.joined(separator: "\n"))
    }
}
