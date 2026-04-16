import SwiftUI
import SwiftData
import SwiftAgent

/// Main entry point for the SwiftAgent Notes demo application.
///
/// Sets up the SwiftData model container, configures the shared
/// ``NoteStore``, and starts the ``NoteAgentManager`` so that all six
/// note tools are available through the in-app agent panel, Siri, and
/// MCP-compatible clients.
@main
struct SwiftAgentNotesApp: App {
    /// The SwiftData container for ``Note`` persistence.
    private let modelContainer: ModelContainer

    /// The agent manager that owns the server, client, and tool catalog.
    @State private var agentManager = NoteAgentManager()

    init() {
        do {
            let schema = Schema([Note.self])
            let config = ModelConfiguration(
                "SwiftAgentNotes",
                schema: schema,
                isStoredInMemoryOnly: false
            )
            modelContainer = try ModelContainer(for: schema, configurations: [config])
            NoteStore.configure(container: modelContainer)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(agentManager)
                .task {
                    await agentManager.start()
                }
        }
        .modelContainer(modelContainer)
    }
}
