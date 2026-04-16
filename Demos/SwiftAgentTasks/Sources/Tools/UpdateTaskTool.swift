import Foundation
import SwiftAgent

/// Agent tool that updates one or more fields of an existing task.
///
/// Only non-empty parameters are applied; omitted or empty fields keep
/// their current values.
@AgentTool("Update fields of an existing task by its ID")
struct UpdateTaskTool {
    @Param("The task's unique identifier") var id: String
    @Param("New title, or empty to keep current") var title: String = ""
    @Param("New notes, or empty to keep current") var notes: String = ""
    @Param("New project name, or empty to keep current") var project: String = ""
    @Param("New priority (low/medium/high), or empty to keep current") var priority: String = ""
    @Param("New due date in ISO 8601 format, or empty to keep current") var dueDate: String = ""

    func perform() async throws -> String {
        let newTitle: String? = title.isEmpty ? nil : title
        let newNotes: String? = notes.isEmpty ? nil : notes
        let newProject: String? = project.isEmpty ? nil : project
        let newPriority: String? = priority.isEmpty ? nil : priority

        var newDueDate: Date??
        if !dueDate.isEmpty {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var parsed = formatter.date(from: dueDate)
            if parsed == nil {
                formatter.formatOptions = [.withInternetDateTime]
                parsed = formatter.date(from: dueDate)
            }
            if parsed == nil {
                formatter.formatOptions = [.withFullDate]
                parsed = formatter.date(from: dueDate)
            }
            newDueDate = .some(parsed)
        }

        try await TaskStore.shared.updateTask(
            id: id,
            title: newTitle,
            notes: newNotes,
            projectName: newProject,
            priority: newPriority,
            dueDate: newDueDate
        )
        return "Task \(id) updated."
    }
}
