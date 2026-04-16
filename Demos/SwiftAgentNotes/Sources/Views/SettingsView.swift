import SwiftUI

/// Settings view for configuring an external MCP server connection.
///
/// The user enters a server URL, taps Connect, and the app establishes
/// an MCP session via ``HTTPClientTransport``. Once connected, remote
/// tools appear alongside local tools in the Agent panel.
struct SettingsView: View {
    @Environment(NoteAgentManager.self) private var manager

    @State private var urlText: String = ""

    var body: some View {
        @Bindable var manager = manager

        Form {
            Section("Remote MCP Server") {
                TextField("Server URL", text: $urlText)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onAppear { urlText = manager.remoteServerURL }

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
                        Task {
                            await manager.disconnectRemote()
                        }
                    }
                } else {
                    Button("Connect") {
                        manager.remoteServerURL = urlText
                        Task {
                            await manager.connectRemote()
                        }
                    }
                    .disabled(urlText.isEmpty)
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
