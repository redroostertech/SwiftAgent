import Foundation
import SwiftData
import SwiftAgent

/// A single note persisted via SwiftData.
///
/// Each note has a title, Markdown body, pinned flag, and automatic
/// timestamps for creation and last update. The ``id`` is a stable
/// `UUID` string suitable for passing through the agent tool surface.
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

    /// Create a new note with the given properties.
    ///
    /// - Parameters:
    ///   - title: The note's headline.
    ///   - body: Markdown body content.
    ///   - pinned: Whether the note should be pinned. Defaults to `false`.
    init(title: String, body: String, pinned: Bool = false) {
        self.id = UUID().uuidString
        self.title = title
        self.body = body
        self.pinned = pinned
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }
}
