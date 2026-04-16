import SwiftUI
import SwiftData
import SwiftAgent

/// The main entry point for SwiftAgent Tasks.
///
/// Sets up the SwiftData model container, configures the shared
/// ``TaskStore``, seeds default projects, registers agent tools,
/// and presents the root ``ContentView``.
@main
struct SwiftAgentTasksApp: App {
    /// The SwiftData model container for task and project persistence.
    let modelContainer: ModelContainer

    /// The agent manager owning local and remote tool surfaces.
    let agentManager: TaskAgentManager

    init() {
        do {
            let schema = Schema([TaskItem.self, Project.self])
            let config = ModelConfiguration(isStoredInMemoryOnly: false)
            self.modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        TaskStore.configure(container: modelContainer)
        self.agentManager = TaskAgentManager()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(agentManager)
                .modelContainer(modelContainer)
                .task {
                    // Seed default projects on first launch.
                    try? await TaskStore.shared.seedDefaultProjects()
                    // Register tools and start the in-process server.
                    await agentManager.setup()
                }
        }
    }
}
