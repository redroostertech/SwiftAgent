import Foundation
import SwiftData

/// Thread-safe data-access layer for ``TaskItem`` and ``Project`` persistence.
///
/// `TaskStore` is a model actor that owns the ``ModelContainer`` and exposes
/// CRUD operations consumed by both SwiftUI views and agent tools. All
/// SwiftData work is isolated to the actor so callers never have to worry
/// about threading.
@ModelActor
actor TaskStore {
    /// Process-wide shared instance. Initialized once at app launch via
    /// ``configure(container:)``.
    static var shared: TaskStore!

    /// One-time setup called from the app entry point.
    ///
    /// - Parameter container: The SwiftData container created by the app.
    static func configure(container: ModelContainer) {
        shared = TaskStore(modelContainer: container)
    }

    // MARK: - Seed data

    /// Seed default projects if none exist. Called once at app launch.
    func seedDefaultProjects() throws {
        let descriptor = FetchDescriptor<Project>()
        let existing = try modelContext.fetch(descriptor)
        guard existing.isEmpty else { return }

        let defaults: [(String, String)] = [
            ("Inbox", "blue"),
            ("Work", "purple"),
            ("Personal", "green")
        ]
        for (name, color) in defaults {
            modelContext.insert(Project(name: name, color: color))
        }
        try modelContext.save()
    }

    // MARK: - Task CRUD

    /// Create a new task and return its identifier.
    ///
    /// - Parameters:
    ///   - title: The task's title text.
    ///   - notes: Optional description. Defaults to empty string.
    ///   - projectName: Project to assign to. Defaults to "Inbox".
    ///   - priority: Priority level. Defaults to "medium".
    ///   - dueDate: Optional due date.
    /// - Returns: The new task's stable `id` string.
    func createTask(
        title: String,
        notes: String = "",
        projectName: String = "Inbox",
        priority: String = "medium",
        dueDate: Date? = nil
    ) throws -> String {
        let task = TaskItem(
            title: title,
            notes: notes,
            projectName: projectName,
            priority: priority,
            dueDate: dueDate
        )
        modelContext.insert(task)
        try modelContext.save()
        return task.id
    }

    /// Fetch tasks with optional filtering.
    ///
    /// - Parameters:
    ///   - projectName: Filter by project name. Pass `nil` for all projects.
    ///   - includeCompleted: Whether to include completed tasks. Defaults to `false`.
    /// - Returns: Tasks sorted by creation date descending.
    func listTasks(projectName: String? = nil, includeCompleted: Bool = false) throws -> [TaskItem] {
        var descriptor = FetchDescriptor<TaskItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        if let projectName, !includeCompleted {
            descriptor.predicate = #Predicate<TaskItem> {
                $0.projectName == projectName && $0.completedAt == nil
            }
        } else if let projectName {
            descriptor.predicate = #Predicate<TaskItem> {
                $0.projectName == projectName
            }
        } else if !includeCompleted {
            descriptor.predicate = #Predicate<TaskItem> {
                $0.completedAt == nil
            }
        }

        return try modelContext.fetch(descriptor)
    }

    /// Fetch a single task by its identifier.
    ///
    /// - Parameter id: The task's `id` string.
    /// - Returns: The matching task, or `nil` if not found.
    func getTask(id: String) throws -> TaskItem? {
        let predicate = #Predicate<TaskItem> { $0.id == id }
        var descriptor = FetchDescriptor<TaskItem>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Mark a task as completed. Idempotent — calling on an already
    /// completed task is a no-op.
    ///
    /// - Parameter id: The task's identifier.
    /// - Throws: ``TaskStoreError/notFound(id:)`` if no matching task exists.
    func completeTask(id: String) throws {
        guard let task = try getTask(id: id) else {
            throw TaskStoreError.notFound(id: id)
        }
        guard task.completedAt == nil else { return }
        task.completedAt = Date()
        task.updatedAt = Date()
        try modelContext.save()
    }

    /// Toggle a task's completion state.
    ///
    /// - Parameter id: The task's identifier.
    /// - Throws: ``TaskStoreError/notFound(id:)`` if no matching task exists.
    func toggleTask(id: String) throws {
        guard let task = try getTask(id: id) else {
            throw TaskStoreError.notFound(id: id)
        }
        if task.completedAt != nil {
            task.completedAt = nil
        } else {
            task.completedAt = Date()
        }
        task.updatedAt = Date()
        try modelContext.save()
    }

    /// Update mutable fields of an existing task.
    ///
    /// Only non-`nil` parameters are applied; omitted fields keep their
    /// current values.
    ///
    /// - Parameters:
    ///   - id: The task's identifier.
    ///   - title: New title, or `nil` to keep the current one.
    ///   - notes: New notes, or `nil` to keep the current ones.
    ///   - projectName: New project name, or `nil` to keep the current one.
    ///   - priority: New priority, or `nil` to keep the current one.
    ///   - dueDate: New due date. Pass `.some(nil)` to clear, `.none` to keep.
    /// - Throws: ``TaskStoreError/notFound(id:)`` if no matching task exists.
    func updateTask(
        id: String,
        title: String? = nil,
        notes: String? = nil,
        projectName: String? = nil,
        priority: String? = nil,
        dueDate: Date?? = nil
    ) throws {
        guard let task = try getTask(id: id) else {
            throw TaskStoreError.notFound(id: id)
        }
        if let title { task.title = title }
        if let notes { task.notes = notes }
        if let projectName { task.projectName = projectName }
        if let priority { task.priority = priority }
        if let dueDate { task.dueDate = dueDate }
        task.updatedAt = Date()
        try modelContext.save()
    }

    /// Delete a task by its identifier.
    ///
    /// - Parameter id: The task's identifier.
    /// - Throws: ``TaskStoreError/notFound(id:)`` if no matching task exists.
    func deleteTask(id: String) throws {
        guard let task = try getTask(id: id) else {
            throw TaskStoreError.notFound(id: id)
        }
        modelContext.delete(task)
        try modelContext.save()
    }

    // MARK: - Project CRUD

    /// Fetch all projects sorted alphabetically by name.
    ///
    /// - Returns: All projects in alphabetical order.
    func listProjects() throws -> [Project] {
        let descriptor = FetchDescriptor<Project>(
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Count of incomplete tasks for a given project.
    ///
    /// - Parameter projectName: The project to count tasks for.
    /// - Returns: Number of incomplete tasks in the project.
    func taskCount(for projectName: String) throws -> Int {
        let predicate = #Predicate<TaskItem> {
            $0.projectName == projectName && $0.completedAt == nil
        }
        let descriptor = FetchDescriptor<TaskItem>(predicate: predicate)
        return try modelContext.fetchCount(descriptor)
    }

    /// Create a new project.
    ///
    /// - Parameters:
    ///   - name: The project's display name.
    ///   - color: A color identifier string. Defaults to "blue".
    /// - Returns: The new project's stable `id` string.
    func createProject(name: String, color: String = "blue") throws -> String {
        let project = Project(name: name, color: color)
        modelContext.insert(project)
        try modelContext.save()
        return project.id
    }

    /// Delete a project by its identifier.
    ///
    /// - Parameter id: The project's identifier.
    /// - Throws: ``TaskStoreError/notFound(id:)`` if no matching project exists.
    func deleteProject(id: String) throws {
        let predicate = #Predicate<Project> { $0.id == id }
        var descriptor = FetchDescriptor<Project>(predicate: predicate)
        descriptor.fetchLimit = 1
        guard let project = try modelContext.fetch(descriptor).first else {
            throw TaskStoreError.notFound(id: id)
        }
        modelContext.delete(project)
        try modelContext.save()
    }
}

/// Errors specific to ``TaskStore`` operations.
enum TaskStoreError: LocalizedError {
    /// No entity exists with the supplied identifier.
    case notFound(id: String)

    var errorDescription: String? {
        switch self {
        case .notFound(let id):
            return "Item not found: \(id)"
        }
    }
}
