import SwiftUI
import SwiftData
import SwiftAgent

/// Root view with note list, editor, and access to AI Chat, Agent tools,
/// and Settings.
struct ContentView: View {
    @State private var selectedNoteID: String?
    @State private var isAgentPanelPresented = false
    @State private var isSettingsPresented = false
    @State private var isChatPresented = false

    @Environment(NoteAgentManager.self) private var agentManager

    var body: some View {
        NavigationSplitView {
            NoteListView(selectedNoteID: $selectedNoteID)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        HStack(spacing: 16) {
                            Button {
                                isChatPresented = true
                            } label: {
                                Label("AI Chat", systemImage: "sparkles")
                            }
                            Button {
                                isAgentPanelPresented = true
                            } label: {
                                Label("Tools", systemImage: "cpu")
                            }
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
        .sheet(isPresented: $isChatPresented) {
            NavigationStack {
                AIChatView()
                    .navigationTitle("AI Chat")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { isChatPresented = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $isAgentPanelPresented) {
            NavigationStack {
                AgentPanelView()
                    .navigationTitle("Agent Tools")
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
