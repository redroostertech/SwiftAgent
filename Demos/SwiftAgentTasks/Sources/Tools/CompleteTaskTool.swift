import Foundation
import SwiftAgent

/// Agent tool that marks a task as complete.
///
/// This operation is idempotent -- calling it on an already-completed task
/// is a no-op and returns a success message.
@AgentTool("Mark a task as complete by its ID")
struct CompleteTaskTool {
    @Param("The task's unique identifier") var id: String

    func perform() async throws -> String {
        try await TaskStore.shared.completeTask(id: id)
        return "Task \(id) marked as complete."
    }
}
