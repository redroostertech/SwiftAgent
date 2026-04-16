import SwiftUI
import SwiftData

/// Root view providing a split navigation layout.
///
/// On iPad, displays a sidebar with projects and a detail pane with
/// the task list. On iPhone, uses a stack-based navigation that
/// pushes from the project list to the task list.
struct ContentView: View {
    /// The currently selected project name.
    @State private var selectedProject: String? = "Inbox"

    /// Whether the agent panel sheet is presented.
    @State private var showingAgentPanel = false

    /// Whether the settings sheet is presented.
    @State private var showingSettings = false

    @Environment(TaskAgentManager.self) private var agentManager

    var body: some View {
        NavigationSplitView {
            ProjectSidebarView(selectedProject: $selectedProject)
                .navigationTitle("Projects")
        } detail: {
            if let project = selectedProject {
                TaskListView(projectName: project)
                    .navigationTitle(project)
            } else {
                ContentUnavailableView(
                    "Select a Project",
                    systemImage: "folder",
                    description: Text("Choose a project from the sidebar to view its tasks.")
                )
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingAgentPanel = true
                } label: {
                    Label("Agent", systemImage: "cpu")
                }

                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        .sheet(isPresented: $showingAgentPanel) {
            NavigationStack {
                AgentPanelView()
                    .navigationTitle("Agent Tools")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingAgentPanel = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingSettings = false }
                        }
                    }
            }
        }
    }
}
