import SwiftUI

/// Settings view for configuring the LLM and MCP server connections.
struct SettingsView: View {
    @Environment(NoteAgentManager.self) private var manager

    @State private var mcpURLText: String = ""
    @State private var llmURLText: String = ""

    var body: some View {
        @Bindable var manager = manager

        Form {
            Section {
                TextField("LLM URL", text: $llmURLText)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .onAppear { llmURLText = manager.llmURL }
                Button("Save") {
                    manager.llmURL = llmURLText
                }
                .disabled(llmURLText.isEmpty)
            } header: {
                Text("LLM Server (llama.cpp)")
            } footer: {
                Text("OpenAI-compatible endpoint, e.g. http://10.0.0.72:8080/v1/chat/completions")
            }

            Section("Remote MCP Server") {
                TextField("MCP Server URL", text: $mcpURLText)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .onAppear { mcpURLText = manager.remoteServerURL }

                HStack {
                    Text("Status")
                    Spacer()
                    Text(manager.remoteStatus)
                        .foregroundStyle(manager.isRemoteConnected ? .green : .secondary)
                }

                if let error = manager.remoteError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section {
                if manager.isRemoteConnected {
                    Button("Disconnect", role: .destructive) {
                        Task { await manager.disconnectRemote() }
                    }
                } else {
                    Button("Connect") {
                        manager.remoteServerURL = mcpURLText
                        Task { await manager.connectRemote() }
                    }
                    .disabled(mcpURLText.isEmpty)
                }
            }

            if manager.isRemoteConnected {
                Section("Remote Tools") {
                    ForEach(manager.remoteTools, id: \.name) { tool in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tool.name)
                                .font(.body.monospaced())
                            Text(tool.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
