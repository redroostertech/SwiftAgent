import Foundation
import SwiftData
import SwiftAgent

/// A single note persisted via SwiftData.
///
/// Each note has a title, Markdown body, pinned flag, automatic
/// timestamps, a semantic embedding vector for similarity search,
/// and explicit links to other notes.
@Model
final class Note {
    /// Stable identifier exposed to agent tools as a plain string.
    var id: String

    /// The note's headline.
    var title: String

    /// Markdown body content.
    var body: String

    /// Whether the note is pinned to the top of the list.
    var pinned: Bool

    /// Timestamp of initial creation.
    var createdAt: Date

    /// Timestamp of the most recent edit.
    var updatedAt: Date

    /// Semantic embedding vector computed from the note's content via
    /// Apple's NaturalLanguage framework. Used for similarity search
    /// and auto-linking. `nil` if the embedding could not be computed.
    var embedding: [Double]?

    /// Identifiers of notes explicitly linked to this one. Links are
    /// bidirectional — if note A links to note B, note B's
    /// `linkedNoteIDs` also contains note A's id.
    var linkedNoteIDs: [String]

    /// Create a new note with the given properties.
    init(title: String, body: String, pinned: Bool = false) {
        self.id = UUID().uuidString
        self.title = title
        self.body = body
        self.pinned = pinned
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
        self.embedding = nil
        self.linkedNoteIDs = []
    }
}
