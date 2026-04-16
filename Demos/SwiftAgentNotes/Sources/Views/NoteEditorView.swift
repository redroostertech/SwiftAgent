import SwiftUI
import SwiftData
import SwiftAgent

/// Detail view for editing a single note's title, body, and pinned state.
///
/// The editor auto-saves changes to SwiftData via the model context.
/// Title uses a `TextField`, body uses a `TextEditor`, and pinned state
/// is a `Toggle`.
struct NoteEditorView: View {
    /// The identifier of the note being edited.
    let noteID: String

    /// Query for the specific note by ID.
    @Query private var notes: [Note]

    /// The model context for saving changes.
    @Environment(\.modelContext) private var modelContext

    /// The note matching ``noteID``, if it still exists.
    private var note: Note? {
        notes.first { $0.id == noteID }
    }

    init(noteID: String) {
        self.noteID = noteID
        // Predicate-based init for the query to fetch only this note.
        let id = noteID
        _notes = Query(filter: #Predicate<Note> { $0.id == id })
    }

    var body: some View {
        if let note {
            NoteEditorForm(note: note)
                .id(note.id)
        } else {
            ContentUnavailableView(
                "Note Not Found",
                systemImage: "doc.text.magnifyingglass",
                description: Text("The selected note may have been deleted.")
            )
        }
    }
}

/// Internal form that binds directly to a ``Note`` model object.
///
/// Separated from ``NoteEditorView`` so that the `note` binding is
/// guaranteed non-optional within this scope.
private struct NoteEditorForm: View {
    /// The note being edited. SwiftData observes property changes
    /// automatically.
    @Bindable var note: Note

    /// The model context for explicit saves after edits.
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Form {
            Section("Title") {
                TextField("Note title", text: $note.title)
                    .font(.title2)
                    .onChange(of: note.title) {
                        markUpdated()
                    }
            }

            Section("Content") {
                TextEditor(text: $note.body)
                    .frame(minHeight: 200)
                    .font(.body)
                    .onChange(of: note.body) {
                        markUpdated()
                    }
            }

            Section {
                Toggle("Pinned", isOn: $note.pinned)
                    .onChange(of: note.pinned) {
                        markUpdated()
                    }
            }

            Section("Info") {
                LabeledContent("Created") {
                    Text(note.createdAt, style: .date)
                }
                LabeledContent("Updated") {
                    Text(note.updatedAt, style: .relative)
                }
                LabeledContent("ID") {
                    Text(note.id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(note.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// Update the note's timestamp and persist changes.
    private func markUpdated() {
        note.updatedAt = Date()
        try? modelContext.save()
    }
}
