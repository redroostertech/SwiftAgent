import AppIntents
import Foundation

/// Siri/Shortcuts intent for creating a new note.
///
/// Invokable via:
///   "Create a note in SwiftAgent Notes"
///   "Make a note called [title]"
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

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let id = try await NoteStore.shared.create(
            title: noteTitle,
            body: body,
            pinned: pinned
        )
        return .result(value: "Created note: \(noteTitle) (id: \(id))")
    }
}
