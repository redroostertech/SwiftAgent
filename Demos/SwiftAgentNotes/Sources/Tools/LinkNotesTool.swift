import Foundation
import SwiftAgent

/// Agent tool that creates a bidirectional link between two notes.
///
/// Linked notes appear in each other's "Related Notes" section in the
/// editor. Links are bidirectional — linking A to B also links B to A.
@AgentTool("Link two notes together as related")
struct LinkNotesTool {
    @Param("ID of the first note") var noteID: String
    @Param("ID of the second note to link to") var toNoteID: String

    func perform() async throws -> String {
        try await NoteStore.shared.link(noteID: noteID, toNoteID: toNoteID)
        return "Notes linked successfully."
    }
}
