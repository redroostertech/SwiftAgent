import Foundation
import SwiftAgent

/// Agent tool that permanently deletes a note by its ID.
///
/// This is a destructive operation that cannot be undone. The tool is
/// annotated accordingly so agents surface a confirmation prompt.
@AgentTool("Delete a note permanently by its ID")
struct DeleteNoteTool {
    @Param("Note ID to delete") var id: String

    func perform() async throws -> String {
        try await NoteStore.shared.delete(id: id)
        return "Note \(id) deleted."
    }
}
