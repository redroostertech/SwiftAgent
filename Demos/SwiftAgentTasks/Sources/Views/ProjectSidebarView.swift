import SwiftUI
import SwiftData

/// Sidebar view listing all projects with their incomplete task counts.
///
/// Displays each project as a selectable row with a colored circle icon
/// and a badge showing the number of open tasks. Includes a button to
/// create new projects.
struct ProjectSidebarView: View {
    /// Binding to the currently selected project name.
    @Binding var selectedProject: String?

    /// All projects from SwiftData, sorted by name.
    @Query(sort: \Project.name) private var projects: [Project]

    /// All incomplete tasks, used for counting per project.
    @Query(filter: #Predicate<TaskItem> { $0.completedAt == nil })
    private var incompleteTasks: [TaskItem]

    /// Whether the add-project alert is shown.
    @State private var showingAddProject = false

    /// Text field content for the new project name.
    @State private var newProjectName = ""

    /// Text field content for the new project color.
    @State private var newProjectColor = "blue"

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List(selection: $selectedProject) {
            ForEach(projects) { project in
                HStack {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(color(for: project.color))
                        .font(.caption)

                    Text(project.name)

                    Spacer()

                    let count = taskCount(for: project.name)
                    if count > 0 {
                        Text("\(count)")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                .tag(project.name)
            }
            .onDelete(perform: deleteProjects)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddProject = true
                } label: {
                    Label("Add Project", systemImage: "plus")
                }
            }
        }
        .alert("New Project", isPresented: $showingAddProject) {
            TextField("Project name", text: $newProjectName)
            Button("Cancel", role: .cancel) {
                newProjectName = ""
            }
            Button("Add") {
                addProject()
            }
        } message: {
            Text("Enter a name for the new project.")
        }
    }

    // MARK: - Helpers

    /// Count incomplete tasks for a given project name.
    private func taskCount(for projectName: String) -> Int {
        incompleteTasks.filter { $0.projectName == projectName }.count
    }

    /// Map a color string to a SwiftUI color.
    private func color(for name: String) -> Color {
        switch name.lowercased() {
        case "blue": return .blue
        case "green": return .green
        case "purple": return .purple
        case "orange": return .orange
        case "red": return .red
        case "yellow": return .yellow
        case "pink": return .pink
        case "indigo": return .indigo
        default: return .blue
        }
    }

    /// Create a new project from the alert input.
    private func addProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let project = Project(name: name, color: newProjectColor)
        modelContext.insert(project)
        newProjectName = ""
    }

    /// Delete projects at the given offsets.
    private func deleteProjects(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(projects[index])
        }
    }
}
