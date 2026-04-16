import Foundation
import SwiftAgent

/// Agent tool that retrieves all notes linked to a given note.
@AgentTool("Get all notes linked to a given note")
struct GetLinkedNotesTool {
    @Param("ID of the note to get links for") var id: String

    func perform() async throws -> String {
        let linked = try await NoteStore.shared.getLinkedNotes(id: id)
        if linked.isEmpty {
            return "No linked notes."
        }
        let lines = linked.map { "\($0.title) (id: \($0.id))" }
        return "Linked notes:\n" + lines.joined(separator: "\n")
    }
}
