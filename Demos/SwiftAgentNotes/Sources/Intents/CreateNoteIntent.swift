import AppIntents
import SwiftData
import Foundation

/// Siri/Shortcuts intent for creating a new note.
///
/// Invokable via:
///   "Create a note in Nolan"
///   "Make a note in Nolan"
struct CreateNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Note"

    static var description = IntentDescription(
        "Create a new note with a title and optional body."
    )

    @Parameter(title: "Title", description: "The note's title")
    var noteTitle: String

    @Parameter(title: "Body", description: "The note's body in markdown", default: "")
    var body: String

    @Parameter(title: "Pinned", description: "Pin the note to the top", default: false)
    var pinned: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Create note titled \(\.$noteTitle)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        do {
            let container = try ModelContainer(for: Note.self)
            let context = ModelContext(container)
            let note = Note(title: noteTitle, body: body, pinned: pinned)
            context.insert(note)
            try context.save()
            return .result(
                value: note.id,
                dialog: "Created note: \(noteTitle)"
            )
        } catch {
            return .result(
                value: "error",
                dialog: "Failed: \(error.localizedDescription)"
            )
        }
    }
}
