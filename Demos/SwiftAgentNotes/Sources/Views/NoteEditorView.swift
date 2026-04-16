import SwiftUI
import SwiftData
import SwiftAgent

/// Detail view for editing a single note's title, body, and pinned state.
/// Also shows linked notes and semantically similar notes.
struct NoteEditorView: View {
    let noteID: String

    @Query private var notes: [Note]
    @Environment(\.modelContext) private var modelContext

    private var note: Note? {
        notes.first { $0.id == noteID }
    }

    init(noteID: String) {
        self.noteID = noteID
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

/// Internal form with the note editor, linked notes, and similar notes.
private struct NoteEditorForm: View {
    @Bindable var note: Note
    @Environment(\.modelContext) private var modelContext
    @Query private var allNotes: [Note]

    @State private var similarNotes: [(id: String, title: String, score: Double)] = []
    @State private var loadingSimilar = false
    @State private var showingPreview = false

    var body: some View {
        Form {
            Section("Title") {
                TextField("Note title", text: $note.title)
                    .font(.title2)
                    .submitLabel(.done)
                    .onChange(of: note.title) { markUpdated() }
            }

            Section {
                if showingPreview {
                    ScrollView {
                        MarkdownView(text: note.body)
                            .padding(.vertical, 4)
                    }
                    .frame(minHeight: 200)
                } else {
                    TextEditor(text: $note.body)
                        .frame(minHeight: 200)
                        .font(.body)
                        .onChange(of: note.body) { markUpdated() }
                }
            } header: {
                HStack {
                    Text("Content")
                    Spacer()
                    Button {
                        showingPreview.toggle()
                    } label: {
                        Label(
                            showingPreview ? "Edit" : "Preview",
                            systemImage: showingPreview ? "pencil" : "eye"
                        )
                        .font(.caption)
                    }
                }
            }

            Section {
                Toggle("Pinned", isOn: $note.pinned)
                    .onChange(of: note.pinned) { markUpdated() }
            }

            // Linked notes
            if !note.linkedNoteIDs.isEmpty {
                Section("Linked Notes") {
                    ForEach(linkedNotes, id: \.id) { linked in
                        Label(linked.title, systemImage: "link")
                            .foregroundStyle(.blue)
                    }
                }
            }

            // Similar notes (computed via embeddings)
            Section {
                if loadingSimilar {
                    ProgressView("Finding similar notes...")
                } else if similarNotes.isEmpty {
                    Text("No similar notes found")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(similarNotes, id: \.id) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.title)
                                Text(String(format: "%.0f%% similar", item.score * 100))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !note.linkedNoteIDs.contains(item.id) {
                                Button {
                                    linkNote(item.id)
                                } label: {
                                    Image(systemName: "link.badge.plus")
                                }
                                .buttonStyle(.borderless)
                            } else {
                                Image(systemName: "link")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            } header: {
                Text("Similar Notes")
            } footer: {
                Text("Powered by Apple NaturalLanguage embeddings")
            }

            Section("Info") {
                LabeledContent("Created") { Text(note.createdAt, style: .date) }
                LabeledContent("Updated") { Text(note.updatedAt, style: .relative) }
                LabeledContent("ID") {
                    Text(note.id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                LabeledContent("Embedding") {
                    Text(note.embedding != nil ? "✓ \(note.embedding!.count)d" : "None")
                        .font(.caption)
                        .foregroundStyle(note.embedding != nil ? .green : .secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(note.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadSimilarNotes() }
    }

    /// Notes that are explicitly linked to this one.
    private var linkedNotes: [Note] {
        allNotes.filter { note.linkedNoteIDs.contains($0.id) }
    }

    /// Link this note to another note bidirectionally.
    private func linkNote(_ otherID: String) {
        Task {
            try? await NoteStore.shared.link(noteID: note.id, toNoteID: otherID)
        }
    }

    /// Load semantically similar notes via embeddings.
    private func loadSimilarNotes() async {
        loadingSimilar = true
        defer { loadingSimilar = false }
        do {
            let results = try await NoteStore.shared.findSimilar(
                toNoteID: note.id, limit: 5
            )
            similarNotes = results.map { (id: $0.note.id, title: $0.note.title, score: $0.similarity) }
        } catch {
            similarNotes = []
        }
    }

    private func markUpdated() {
        note.updatedAt = Date()
        try? modelContext.save()
    }
}
