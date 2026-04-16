import Foundation
import SwiftAgent

/// Agent tool that permanently deletes a task by its identifier.
///
/// This operation is destructive and cannot be undone.
@AgentTool("Delete a task permanently by its ID")
struct DeleteTaskTool {
    @Param("The task's unique identifier") var id: String

    func perform() async throws -> String {
        try await TaskStore.shared.deleteTask(id: id)
        return "Task \(id) deleted."
    }
}
