import AppIntents
import SwiftData
import Foundation
import os

/// Logger for AppIntent debugging. View in Console.app on Mac
/// with iPhone connected, filter for "NoteIntents".
private let logger = Logger(subsystem: "com.swiftagent.demos.notes", category: "NoteIntents")

/// Siri/Shortcuts intent for creating a new note.
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
        logger.info("CreateNoteIntent.perform() called with title: \(self.noteTitle)")

        do {
            logger.info("Creating ModelContainer...")
            let schema = Schema([Note.self])
            let config = ModelConfiguration(
                "SwiftAgentNotes",
                schema: schema,
                isStoredInMemoryOnly: false
            )
            let container = try ModelContainer(for: schema, configurations: [config])
            logger.info("ModelContainer created successfully")

            let context = ModelContext(container)
            let note = Note(title: noteTitle, body: body, pinned: pinned)
            context.insert(note)
            try context.save()

            logger.info("Note saved with id: \(note.id)")
            return .result(
                value: note.id,
                dialog: "Created note: \(noteTitle)"
            )
        } catch {
            logger.error("CreateNoteIntent failed: \(error.localizedDescription)")
            return .result(
                value: "error: \(error.localizedDescription)",
                dialog: "Error: \(error.localizedDescription)"
            )
        }
    }
}
