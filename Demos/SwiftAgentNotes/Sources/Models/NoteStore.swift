import Foundation
import SwiftData
import SwiftAgent

/// Thread-safe data-access layer for ``Note`` persistence.
///
/// `NoteStore` is a global actor that owns the ``ModelContainer`` and
/// exposes CRUD operations consumed by both SwiftUI views and agent
/// tools. All SwiftData work is isolated to the actor so callers never
/// have to worry about threading.
@ModelActor
actor NoteStore {
    /// Process-wide shared instance. Initialized once at app launch via
    /// ``configure(container:)``.
    static var shared: NoteStore!

    /// One-time setup called from the app entry point.
    ///
    /// - Parameter container: The SwiftData container created by the app.
    static func configure(container: ModelContainer) {
        shared = NoteStore(modelContainer: container)
    }

    // MARK: - Create

    /// Create a new note and return its identifier.
    ///
    /// - Parameters:
    ///   - title: The note's headline.
    ///   - body: Markdown body content.
    ///   - pinned: Whether the note should be pinned.
    /// - Returns: The new note's stable `id` string.
    func create(title: String, body: String, pinned: Bool = false) throws -> String {
        let note = Note(title: title, body: body, pinned: pinned)
        modelContext.insert(note)
        try modelContext.save()
        return note.id
    }

    // MARK: - Read

    /// Fetch all notes sorted by pinned-first, then most recently updated.
    ///
    /// - Parameter limit: Optional cap on the number of results.
    /// - Returns: An array of notes in display order.
    func list(limit: Int? = nil) throws -> [Note] {
        var descriptor = FetchDescriptor<Note>(
            sortBy: [
                SortDescriptor(\.pinned, order: .reverse),
                SortDescriptor(\.updatedAt, order: .reverse)
            ]
        )
        if let limit {
            descriptor.fetchLimit = limit
        }
        return try modelContext.fetch(descriptor)
    }

    /// Fetch a single note by its identifier.
    ///
    /// - Parameter id: The note's `id` string.
    /// - Returns: The matching note, or `nil` if not found.
    func get(id: String) throws -> Note? {
        let predicate = #Predicate<Note> { $0.id == id }
        var descriptor = FetchDescriptor<Note>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Full-text search across title and body.
    ///
    /// - Parameter query: The search string. Matched case-insensitively
    ///   against both ``Note/title`` and ``Note/body``.
    /// - Returns: Matching notes sorted by update date descending.
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

    // MARK: - Update

    /// Update mutable fields of an existing note.
    ///
    /// Only non-`nil` parameters are applied; omitted fields keep their
    /// current values.
    ///
    /// - Parameters:
    ///   - id: The note's identifier.
    ///   - title: New title, or `nil` to keep the current one.
    ///   - body: New body, or `nil` to keep the current one.
    ///   - pinned: New pinned state, or `nil` to keep the current one.
    /// - Throws: If the note is not found or save fails.
    func update(id: String, title: String?, body: String?, pinned: Bool?) throws {
        guard let note = try get(id: id) else {
            throw NoteStoreError.notFound(id: id)
        }
        if let title { note.title = title }
        if let body { note.body = body }
        if let pinned { note.pinned = pinned }
        note.updatedAt = Date()
        try modelContext.save()
    }

    // MARK: - Delete

    /// Delete a note by its identifier.
    ///
    /// - Parameter id: The note's identifier.
    /// - Throws: ``NoteStoreError/notFound(id:)`` if no matching note exists.
    func delete(id: String) throws {
        guard let note = try get(id: id) else {
            throw NoteStoreError.notFound(id: id)
        }
        modelContext.delete(note)
        try modelContext.save()
    }
}

/// Errors specific to ``NoteStore`` operations.
enum NoteStoreError: LocalizedError {
    /// No note exists with the supplied identifier.
    case notFound(id: String)

    var errorDescription: String? {
        switch self {
        case .notFound(let id):
            return "Note not found: \(id)"
        }
    }
}
