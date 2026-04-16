import SwiftUI
import SwiftData
import SwiftAgent

/// Sidebar view displaying the list of notes with search, swipe-to-delete,
/// and pin badges.
///
/// Notes are sorted pinned-first, then by most recently updated. A search
/// bar filters by title and body content. Tapping a row selects the note
/// for editing in the detail pane.
struct NoteListView: View {
    /// Binding to the parent's selected note identifier.
    @Binding var selectedNoteID: String?

    /// All notes fetched from SwiftData, sorted by most recently updated.
    /// Pinned-first ordering is applied in the computed `sortedNotes`.
    @Query(sort: [
        SortDescriptor(\Note.updatedAt, order: .reverse)
    ])
    private var notes: [Note]

    /// Notes reordered so pinned items appear first.
    private var sortedNotes: [Note] {
        notes.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    /// The model context used for delete operations.
    @Environment(\.modelContext) private var modelContext

    /// Current search text.
    @State private var searchText = ""

    /// Notes filtered by the current search query, with pinned-first ordering.
    private var filteredNotes: [Note] {
        guard !searchText.isEmpty else { return sortedNotes }
        let query = searchText.localizedLowercase
        return sortedNotes.filter {
            $0.title.localizedStandardContains(query) ||
            $0.body.localizedStandardContains(query)
        }
    }

    var body: some View {
        List(selection: $selectedNoteID) {
            ForEach(filteredNotes, id: \.id) { note in
                NavigationLink(value: note.id) {
                    NoteRow(note: note)
                }
            }
            .onDelete(perform: deleteNotes)
        }
        .searchable(text: $searchText, prompt: "Search notes")
        .navigationTitle("Notes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    createNote()
                } label: {
                    Label("New Note", systemImage: "plus")
                }
            }
        }
        .overlay {
            if filteredNotes.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if filteredNotes.isEmpty && searchText.isEmpty {
                ContentUnavailableView(
                    "No Notes",
                    systemImage: "doc.text",
                    description: Text("Tap + to create your first note.")
                )
            }
        }
    }

    // MARK: - Actions

    /// Create a new untitled note and select it.
    private func createNote() {
        let note = Note(title: "Untitled", body: "")
        modelContext.insert(note)
        try? modelContext.save()
        selectedNoteID = note.id
    }

    /// Delete notes at the given offsets from the filtered list.
    private func deleteNotes(at offsets: IndexSet) {
        for index in offsets {
            let note = filteredNotes[index]
            if selectedNoteID == note.id {
                selectedNoteID = nil
            }
            modelContext.delete(note)
        }
        try? modelContext.save()
    }
}

/// A single row in the note list showing the title, a snippet of the body,
/// and a pin badge when applicable.
private struct NoteRow: View {
    /// The note to display.
    let note: Note

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(note.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(note.body.isEmpty ? "No content" : note.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if note.pinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}
