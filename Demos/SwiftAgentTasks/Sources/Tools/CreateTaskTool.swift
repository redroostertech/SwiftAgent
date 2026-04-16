import Foundation
import SwiftAgent

/// Agent tool that creates a new task in the task store.
///
/// Accepts a title and optional project, priority, due date, and notes.
/// Returns the newly created task's identifier on success.
@AgentTool("Create a new task with a title, optional project, priority, due date, and notes")
struct CreateTaskTool {
    @Param("Task title") var title: String
    @Param("Project name to assign the task to") var project: String = "Inbox"
    @Param("Priority level: low, medium, or high") var priority: String = "medium"
    @Param("Due date in ISO 8601 format") var dueDate: String = ""
    @Param("Additional notes or description") var notes: String = ""

    func perform() async throws -> String {
        var parsedDate: Date?
        if !dueDate.isEmpty {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            parsedDate = formatter.date(from: dueDate)
            if parsedDate == nil {
                formatter.formatOptions = [.withInternetDateTime]
                parsedDate = formatter.date(from: dueDate)
            }
            if parsedDate == nil {
                formatter.formatOptions = [.withFullDate]
                parsedDate = formatter.date(from: dueDate)
            }
        }

        let id = try await TaskStore.shared.createTask(
            title: title,
            notes: notes,
            projectName: project,
            priority: priority,
            dueDate: parsedDate
        )
        return "Created task \(id)"
    }
}
