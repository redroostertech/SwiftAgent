import Foundation
import SwiftAgent

/// Agent tool that fetches a single task by its identifier.
///
/// Returns the full task details including all fields.
@AgentTool("Fetch a single task by its ID")
struct GetTaskTool {
    @Param("The task's unique identifier") var id: String

    func perform() async throws -> String {
        guard let task = try await TaskStore.shared.getTask(id: id) else {
            return "Task not found: \(id)"
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var lines = [
            "id: \(task.id)",
            "title: \(task.title)",
            "project: \(task.projectName)",
            "priority: \(task.priority)",
            "notes: \(task.notes)",
            "created: \(formatter.string(from: task.createdAt))",
            "updated: \(formatter.string(from: task.updatedAt))"
        ]
        if let due = task.dueDate {
            lines.append("due: \(formatter.string(from: due))")
        }
        if let completed = task.completedAt {
            lines.append("completed: \(formatter.string(from: completed))")
        } else {
            lines.append("status: open")
        }
        return lines.joined(separator: "\n")
    }
}
