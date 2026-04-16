import SwiftUI
import SwiftData
import SwiftAgent

/// Root view presenting a two-column navigation split with a sidebar of
/// notes and a detail editor.
///
/// The sidebar lists all notes via ``NoteListView`` and the detail pane
/// shows ``NoteEditorView`` for the selected note. Toolbar buttons
/// provide access to the Agent panel and Settings.
struct ContentView: View {
    /// The currently selected note identifier.
    @State private var selectedNoteID: String?

    /// Whether the agent panel sheet is presented.
    @State private var isAgentPanelPresented = false

    /// Whether the settings sheet is presented.
    @State private var isSettingsPresented = false

    /// The agent manager driving the tool panel.
    @Environment(NoteAgentManager.self) private var agentManager

    var body: some View {
        NavigationSplitView {
            NoteListView(selectedNoteID: $selectedNoteID)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            isAgentPanelPresented = true
                        } label: {
                            Label("Agent", systemImage: "cpu")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            isSettingsPresented = true
                        } label: {
                            Label("Settings", systemImage: "gear")
                        }
                    }
                }
        } detail: {
            if let noteID = selectedNoteID {
                NoteEditorView(noteID: noteID)
            } else {
                ContentUnavailableView(
                    "No Note Selected",
                    systemImage: "doc.text",
                    description: Text("Select a note from the sidebar or create a new one.")
                )
            }
        }
        .sheet(isPresented: $isAgentPanelPresented) {
            NavigationStack {
                AgentPanelView()
                    .navigationTitle("Agent")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { isAgentPanelPresented = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            NavigationStack {
                SettingsView()
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { isSettingsPresented = false }
                        }
                    }
            }
        }
    }
}
