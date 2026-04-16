import Foundation
import SwiftAgent

/// Agent tool that creates a new note with a title and body.
///
/// Returns the newly created note's identifier on success.
@AgentTool("Create a new note with a title and body")
struct CreateNoteTool {
    @Param("Note title") var title: String
    @Param("Markdown body") var body: String
    @Param("Pin to top of list") var pinned: Bool = false

    func perform() async throws -> String {
        let id = try await NoteStore.shared.create(
            title: title,
            body: body,
            pinned: pinned
        )
        return id
    }
}
