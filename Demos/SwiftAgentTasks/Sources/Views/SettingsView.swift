import SwiftUI

/// Settings view for configuring the remote MCP server connection.
///
/// Provides a text field for the server URL, connect/disconnect controls,
/// and status display. The URL is persisted via UserDefaults so it
/// survives app restarts.
struct SettingsView: View {
    @Environment(TaskAgentManager.self) private var agentManager

    /// The URL text field content (local state, committed on connect).
    @State private var urlText: String = ""

    /// Whether a connection attempt is in progress.
    @State private var isConnecting = false

    var body: some View {
        Form {
            // Remote server section
            Section {
                TextField("https://example.com/mcp", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                HStack {
                    Text("Status:")
                        .foregroundStyle(.secondary)
                    Text(agentManager.remoteStatus)
                        .foregroundStyle(agentManager.isRemoteConnected ? .green : .secondary)
                }

                if agentManager.isRemoteConnected {
                    Button("Disconnect", role: .destructive) {
                        Task {
                            await agentManager.disconnectRemote()
                        }
                    }
                } else {
                    Button {
                        connect()
                    } label: {
                        HStack {
                            if isConnecting {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text("Connect")
                        }
                    }
                    .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isConnecting)
                }
            } header: {
                Label("Remote MCP Server", systemImage: "cloud")
            } footer: {
                Text("Enter the URL of an MCP server to discover and invoke its tools alongside your local ones.")
            }

            // Error display
            if let error = agentManager.lastError {
                Section("Last Error") {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            // Local tools info
            Section {
                HStack {
                    Text("Local tools registered:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(agentManager.localTools.count)")
                        .fontWeight(.medium)
                }
                if agentManager.isRemoteConnected {
                    HStack {
                        Text("Remote tools available:")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(agentManager.remoteTools.count)")
                            .fontWeight(.medium)
                    }
                }
            } header: {
                Label("Agent Info", systemImage: "cpu")
            }
        }
        .onAppear {
            urlText = agentManager.remoteServerURL
        }
    }

    // MARK: - Actions

    /// Attempt to connect to the remote server.
    private func connect() {
        let url = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        isConnecting = true
        Task {
            await agentManager.connectRemote(urlString: url)
            await MainActor.run {
                isConnecting = false
            }
        }
    }
}
