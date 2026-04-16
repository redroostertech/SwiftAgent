import AppIntents

/// Declares the app shortcuts that Siri and Shortcuts discover
/// automatically when the app is installed.
///
/// These phrases work with Siri voice and appear in the Shortcuts
/// app as available actions without any user configuration.
struct NotesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateNoteIntent(),
            phrases: [
                "Create a note in \(.applicationName)",
                "Make a note in \(.applicationName)",
                "New note in \(.applicationName)"
            ],
            shortTitle: "Create Note",
            systemImageName: "plus.square"
        )

        AppShortcut(
            intent: ListNotesIntent(),
            phrases: [
                "Show my notes in \(.applicationName)",
                "List notes in \(.applicationName)",
                "What notes do I have in \(.applicationName)"
            ],
            shortTitle: "List Notes",
            systemImageName: "list.bullet"
        )

        AppShortcut(
            intent: SearchNotesIntent(),
            phrases: [
                "Search notes in \(.applicationName)",
                "Find notes in \(.applicationName)",
                "Search my notes in \(.applicationName)"
            ],
            shortTitle: "Search Notes",
            systemImageName: "magnifyingglass"
        )
    }
}
