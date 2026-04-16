import Foundation
import SwiftAgent

/// Agent tool that updates an existing note's title, body, or pinned state.
///
/// Only the fields provided are changed; omitted fields keep their
/// current values.
@AgentTool("Update a note's title, body, or pinned state by ID")
struct UpdateNoteTool {
    @Param("Note ID to update") var id: String
    @Param("New title") var title: String = ""
    @Param("New markdown body") var body: String = ""
    @Param("New pinned state") var pinned: Bool = false

    func perform() async throws -> String {
        let newTitle: String? = title.isEmpty ? nil : title
        let newBody: String? = body.isEmpty ? nil : body
        // pinned is always applied when explicitly provided by the caller;
        // the macro passes the default (false) when the caller omits it.
        try await NoteStore.shared.update(
            id: id,
            title: newTitle,
            body: newBody,
            pinned: pinned
        )
        return "Note \(id) updated."
    }
}
