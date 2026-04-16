import Foundation
import SwiftData

/// A single task persisted via SwiftData.
///
/// Named `TaskItem` to avoid colliding with Swift's built-in `Task` type.
/// Each task belongs to a project (by name), carries a priority level, and
/// tracks creation, update, and completion timestamps. The ``id`` is a
/// stable UUID string suitable for passing through the agent tool surface.
@Model
final class TaskItem {
    /// Stable identifier exposed to agent tools as a plain string.
    var id: String

    /// The task's title text.
    var title: String

    /// Optional longer notes or description for the task.
    var notes: String

    /// The name of the project this task belongs to (e.g. "Inbox", "Work").
    var projectName: String

    /// Priority level: "low", "medium", or "high".
    var priority: String

    /// Optional due date for the task.
    var dueDate: Date?

    /// Timestamp when the task was marked complete, or `nil` if still open.
    var completedAt: Date?

    /// Timestamp of initial creation.
    var createdAt: Date

    /// Timestamp of the most recent edit.
    var updatedAt: Date

    /// Create a new task with the given properties.
    ///
    /// - Parameters:
    ///   - title: The task's title text.
    ///   - notes: Optional longer description. Defaults to empty string.
    ///   - projectName: The project this task belongs to. Defaults to "Inbox".
    ///   - priority: Priority level. Defaults to "medium".
    ///   - dueDate: Optional due date. Defaults to `nil`.
    init(
        title: String,
        notes: String = "",
        projectName: String = "Inbox",
        priority: String = "medium",
        dueDate: Date? = nil
    ) {
        self.id = UUID().uuidString
        self.title = title
        self.notes = notes
        self.projectName = projectName
        self.priority = priority
        self.dueDate = dueDate
        self.completedAt = nil
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }

    /// Whether this task has been completed.
    var isCompleted: Bool {
        completedAt != nil
    }
}
