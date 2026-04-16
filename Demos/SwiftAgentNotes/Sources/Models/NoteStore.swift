import Foundation
import SwiftData
import SwiftAgent

/// Thread-safe data-access layer for ``Note`` persistence.
///
/// `NoteStore` is a `@ModelActor` that owns the ``ModelContainer`` and
/// exposes CRUD operations, semantic search via embeddings, and note
/// linking. All SwiftData work is isolated to the actor.
@ModelActor
actor NoteStore {
    /// Process-wide shared instance. Self-initializes on first access
    /// so AppIntents invoked by Siri (which may skip the app's init)
    /// always have a working store.
    private static var _shared: NoteStore?

    static var shared: NoteStore {
        if let existing = _shared { return existing }
        let store = NoteStore(modelContainer: Self.makeContainer())
        _shared = store
        return store
    }

    /// Configure with a specific container (called from app launch).
    /// If already initialized, this is a no-op.
    static func configure(container: ModelContainer) {
        if _shared == nil {
            _shared = NoteStore(modelContainer: container)
        }
    }

    /// Build the default ModelContainer for Notes.
    private static func makeContainer() -> ModelContainer {
        do {
            let schema = Schema([Note.self])
            let config = ModelConfiguration(
                "SwiftAgentNotes",
                schema: schema,
                isStoredInMemoryOnly: false
            )
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    // MARK: - Create

    /// Create a new note, compute its embedding, and return its identifier.
    func create(title: String, body: String, pinned: Bool = false) throws -> String {
        let note = Note(title: title, body: body, pinned: pinned)
        note.embedding = EmbeddingService.shared.embedNote(title: title, body: body)
        modelContext.insert(note)
        try modelContext.save()
        return note.id
    }

    // MARK: - Read

    /// Fetch all notes sorted by most recently updated. Pinned-first
    /// ordering is applied in memory.
    func list(limit: Int? = nil) throws -> [Note] {
        var descriptor = FetchDescriptor<Note>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        if let limit { descriptor.fetchLimit = limit }
        let results = try modelContext.fetch(descriptor)
        return results.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    /// Fetch a single note by its identifier.
    func get(id: String) throws -> Note? {
        let predicate = #Predicate<Note> { $0.id == id }
        var descriptor = FetchDescriptor<Note>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Full-text search across title and body.
    func search(query: String) throws -> [Note] {
        let lowered = query.localizedLowercase
        let predicate = #Predicate<Note> {
            $0.title.localizedStandardContains(lowered) ||
            $0.body.localizedStandardContains(lowered)
        }
        let descriptor = FetchDescriptor<Note>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Semantic search

    /// Find notes semantically similar to a query string using
    /// embedding cosine similarity.
    ///
    /// Falls back to text search if embeddings are unavailable.
    func semanticSearch(query: String, limit: Int = 5) throws -> [(note: Note, similarity: Double)] {
        guard let queryEmbedding = EmbeddingService.shared.embed(query) else {
            let textResults = try search(query: query)
            return textResults.prefix(limit).map { ($0, 1.0) }
        }
        let allNotes = try modelContext.fetch(FetchDescriptor<Note>())
        return EmbeddingService.shared.findSimilar(
            to: queryEmbedding, in: allNotes, threshold: 0.3, limit: limit
        )
    }

    /// Find notes similar to a given note by its ID.
    func findSimilar(toNoteID id: String, limit: Int = 5) throws -> [(note: Note, similarity: Double)] {
        guard let note = try get(id: id), let embedding = note.embedding else {
            return []
        }
        let allNotes = try modelContext.fetch(FetchDescriptor<Note>())
        let others = allNotes.filter { $0.id != id }
        return EmbeddingService.shared.findSimilar(
            to: embedding, in: others, threshold: 0.3, limit: limit
        )
    }

    // MARK: - Update

    /// Update mutable fields of an existing note. Only non-`nil`
    /// parameters are applied. Recomputes the embedding if content
    /// changed.
    func update(id: String, title: String?, body: String?, pinned: Bool?) throws {
        guard let note = try get(id: id) else {
            throw NoteStoreError.notFound(id: id)
        }
        let contentChanged = (title != nil && title != note.title) ||
                             (body != nil && body != note.body)
        if let title { note.title = title }
        if let body { note.body = body }
        if let pinned { note.pinned = pinned }
        note.updatedAt = Date()
        if contentChanged {
            note.embedding = EmbeddingService.shared.embedNote(
                title: note.title, body: note.body
            )
        }
        try modelContext.save()
    }

    // MARK: - Delete

    /// Delete a note by its identifier. Also removes links from other
    /// notes pointing to this one.
    func delete(id: String) throws {
        guard let note = try get(id: id) else {
            throw NoteStoreError.notFound(id: id)
        }
        // Clean up bidirectional links.
        for linkedID in note.linkedNoteIDs {
            if let linked = try get(id: linkedID) {
                linked.linkedNoteIDs.removeAll { $0 == id }
            }
        }
        modelContext.delete(note)
        try modelContext.save()
    }

    // MARK: - Linking

    /// Create a bidirectional link between two notes.
    func link(noteID: String, toNoteID: String) throws {
        guard let noteA = try get(id: noteID) else {
            throw NoteStoreError.notFound(id: noteID)
        }
        guard let noteB = try get(id: toNoteID) else {
            throw NoteStoreError.notFound(id: toNoteID)
        }
        if !noteA.linkedNoteIDs.contains(toNoteID) {
            noteA.linkedNoteIDs.append(toNoteID)
        }
        if !noteB.linkedNoteIDs.contains(noteID) {
            noteB.linkedNoteIDs.append(noteID)
        }
        try modelContext.save()
    }

    /// Remove a bidirectional link between two notes.
    func unlink(noteID: String, fromNoteID: String) throws {
        if let noteA = try get(id: noteID) {
            noteA.linkedNoteIDs.removeAll { $0 == fromNoteID }
        }
        if let noteB = try get(id: fromNoteID) {
            noteB.linkedNoteIDs.removeAll { $0 == noteID }
        }
        try modelContext.save()
    }

    /// Get all notes linked to a given note.
    func getLinkedNotes(id: String) throws -> [Note] {
        guard let note = try get(id: id) else {
            throw NoteStoreError.notFound(id: id)
        }
        return try note.linkedNoteIDs.compactMap { try get(id: $0) }
    }

    // MARK: - Embedding backfill

    /// Recompute embeddings for all notes that don't have one.
    /// Call on first launch after adding embedding support.
    func backfillEmbeddings() throws {
        let predicate = #Predicate<Note> { $0.embedding == nil }
        let notes = try modelContext.fetch(FetchDescriptor<Note>(predicate: predicate))
        for note in notes {
            note.embedding = EmbeddingService.shared.embedNote(
                title: note.title, body: note.body
            )
        }
        if !notes.isEmpty {
            try modelContext.save()
        }
    }
}

/// Errors specific to ``NoteStore`` operations.
enum NoteStoreError: LocalizedError {
    /// No note exists with the supplied identifier.
    case notFound(id: String)

    var errorDescription: String? {
        switch self {
        case .notFound(let id): return "Note not found: \(id)"
        }
    }
}
