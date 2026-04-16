import SwiftUI
import SwiftData

/// Displays the list of tasks for a selected project.
///
/// Features a quick-add text field at the top for rapid task creation,
/// a toggle for showing completed tasks, and swipe-to-delete on each row.
struct TaskListView: View {
    /// The project whose tasks are displayed.
    let projectName: String

    /// All tasks for this project, sorted by creation date descending.
    @Query private var allTasks: [TaskItem]

    /// Quick-add text field content.
    @State private var newTaskTitle = ""

    /// Whether to show completed tasks.
    @State private var showCompleted = false

    @Environment(\.modelContext) private var modelContext

    init(projectName: String) {
        self.projectName = projectName
        let name = projectName
        _allTasks = Query(
            filter: #Predicate<TaskItem> { $0.projectName == name },
            sort: [SortDescriptor(\TaskItem.createdAt, order: .reverse)]
        )
    }

    /// Filtered tasks based on completion toggle.
    private var visibleTasks: [TaskItem] {
        if showCompleted {
            return allTasks
        }
        return allTasks.filter { $0.completedAt == nil }
    }

    var body: some View {
        List {
            // Quick-add bar
            Section {
                HStack {
                    TextField("Add a task...", text: $newTaskTitle)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            addTask()
                        }

                    if !newTaskTitle.isEmpty {
                        Button {
                            addTask()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Task rows
            Section {
                if visibleTasks.isEmpty {
                    ContentUnavailableView {
                        Label("No Tasks", systemImage: "checkmark.circle")
                    } description: {
                        Text("Add a task above or use the Agent panel.")
                    }
                } else {
                    ForEach(visibleTasks) { task in
                        TaskRowView(task: task)
                    }
                    .onDelete(perform: deleteTasks)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Toggle(isOn: $showCompleted) {
                    Label("Show Completed", systemImage: "eye")
                }
            }
        }
        .animation(.default, value: showCompleted)
    }

    // MARK: - Actions

    /// Create a new task from the quick-add field.
    private func addTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let task = TaskItem(title: title, projectName: projectName)
        modelContext.insert(task)
        newTaskTitle = ""
    }

    /// Delete tasks at the given offsets.
    private func deleteTasks(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(visibleTasks[index])
        }
    }
}
