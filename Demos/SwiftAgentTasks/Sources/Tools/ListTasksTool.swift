import Foundation
import SwiftAgent

/// Agent tool that lists tasks with optional filtering by project and completion status.
///
/// Returns a JSON-formatted list of task summaries including id, title,
/// project, priority, due date, and completion state.
@AgentTool("List tasks, optionally filtered by project and completion status")
struct ListTasksTool {
    @Param("Project name to filter by, or empty for all") var project: String = ""
    @Param("Whether to include completed tasks") var includeCompleted: Bool = false

    func perform() async throws -> String {
        let projectFilter: String? = project.isEmpty ? nil : project
        let tasks = try await TaskStore.shared.listTasks(
            projectName: projectFilter,
            includeCompleted: includeCompleted
        )

        if tasks.isEmpty {
            return "No tasks found."
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let lines = tasks.map { task in
            var parts = [
                "id: \(task.id)",
                "title: \(task.title)",
                "project: \(task.projectName)",
                "priority: \(task.priority)"
            ]
            if let due = task.dueDate {
                parts.append("due: \(formatter.string(from: due))")
            }
            if let completed = task.completedAt {
                parts.append("completed: \(formatter.string(from: completed))")
            }
            return parts.joined(separator: ", ")
        }
        return "Found \(tasks.count) task(s):\n" + lines.joined(separator: "\n")
    }
}
