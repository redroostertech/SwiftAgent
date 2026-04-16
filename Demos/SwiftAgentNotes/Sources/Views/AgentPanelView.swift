import SwiftUI
import SwiftAgent

/// Sheet view that lets the user browse registered agent tools,
/// fill in arguments via auto-generated form fields, invoke the
/// selected tool, and see the result.
///
/// Form fields are derived at runtime from each tool's
/// ``MCPToolDescriptor/inputSchema`` so the UI automatically adapts
/// when tools are added or changed.
struct AgentPanelView: View {
    /// The agent manager supplying tools and handling invocations.
    @Environment(NoteAgentManager.self) private var manager

    /// Dismiss action for the sheet.
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var manager = manager

        Form {
            if !manager.isReady {
                Section {
                    if let error = manager.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    } else {
                        ProgressView("Starting agent...")
                    }
                }
            } else {
                toolPickerSection
                argumentsSection
                invokeSection
                resultSection
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Sections

    /// Picker for choosing which tool to invoke, split by local/remote.
    @ViewBuilder
    private var toolPickerSection: some View {
        @Bindable var manager = manager

        Section {
            Picker("Select tool", selection: $manager.selectedToolName) {
                if !manager.localTools.isEmpty {
                    Section("Local Tools") {
                        ForEach(manager.localTools, id: \.name) { tool in
                            Label(displayName(for: tool), systemImage: "cpu")
                                .tag(Optional(tool.name))
                        }
                    }
                }
                if !manager.remoteTools.isEmpty {
                    Section("Remote Tools") {
                        ForEach(manager.remoteTools, id: \.name) { tool in
                            Label(displayName(for: tool), systemImage: "cloud")
                                .tag(Optional(tool.name))
                        }
                    }
                }
            }
            .pickerStyle(.menu)
            .onChange(of: manager.selectedToolName) { _, newValue in
                if let name = newValue {
                    manager.selectTool(name)
                }
            }

            if let tool = manager.selectedTool {
                HStack {
                    Image(systemName: manager.isSelectedToolRemote ? "cloud" : "cpu")
                        .foregroundStyle(manager.isSelectedToolRemote ? .blue : .green)
                    Text(tool.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Tool")
        } footer: {
            if manager.remoteTools.isEmpty && !manager.isRemoteConnected {
                Text("Connect to a remote MCP server in Settings to see remote tools here.")
            }
        }
    }

    /// Auto-generated form fields for the selected tool's parameters.
    @ViewBuilder
    private var argumentsSection: some View {
        @Bindable var manager = manager
        let properties = manager.selectedToolProperties

        if !properties.isEmpty {
            Section("Arguments") {
                ForEach(properties, id: \.name) { prop in
                    fieldView(
                        name: prop.name,
                        schema: prop.schema,
                        isRequired: prop.isRequired,
                        values: $manager.argumentValues
                    )
                }
            }
        }
    }

    /// The invoke button with loading state.
    private var invokeSection: some View {
        Section {
            Button {
                Task {
                    await manager.invoke()
                }
            } label: {
                HStack {
                    Spacer()
                    if manager.isInvoking {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(manager.isInvoking ? "Running..." : "Invoke")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .disabled(manager.isInvoking || manager.selectedTool == nil)
        }
    }

    /// The result display area.
    @ViewBuilder
    private var resultSection: some View {
        if let result = manager.resultText {
            Section(manager.resultIsError ? "Error" : "Result") {
                Text(result)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(manager.resultIsError ? .red : .primary)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Field rendering

    /// Build a form field appropriate for the given schema type.
    ///
    /// - Parameters:
    ///   - name: The parameter name.
    ///   - schema: The JSON schema for this parameter.
    ///   - isRequired: Whether the parameter is required.
    ///   - values: Binding to the argument values dictionary.
    @ViewBuilder
    private func fieldView(
        name: String,
        schema: MCPSchema,
        isRequired: Bool,
        values: Binding<[String: String]>
    ) -> some View {
        let label = schema.description ?? name
        let requiredMarker = isRequired ? " *" : ""

        switch schema.type {
        case .boolean:
            Toggle(
                "\(label)\(requiredMarker)",
                isOn: Binding<Bool>(
                    get: {
                        let val = values.wrappedValue[name] ?? ""
                        return ["true", "yes", "1"].contains(val.lowercased())
                    },
                    set: { newValue in
                        values.wrappedValue[name] = newValue ? "true" : "false"
                    }
                )
            )

        case .integer:
            TextField(
                "\(label)\(requiredMarker)",
                text: Binding<String>(
                    get: { values.wrappedValue[name] ?? "" },
                    set: { values.wrappedValue[name] = $0 }
                )
            )
            #if os(iOS)
            .keyboardType(.numberPad)
            #endif

        case .number:
            TextField(
                "\(label)\(requiredMarker)",
                text: Binding<String>(
                    get: { values.wrappedValue[name] ?? "" },
                    set: { values.wrappedValue[name] = $0 }
                )
            )
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif

        default:
            TextField(
                "\(label)\(requiredMarker)",
                text: Binding<String>(
                    get: { values.wrappedValue[name] ?? "" },
                    set: { values.wrappedValue[name] = $0 }
                ),
                axis: .vertical
            )
        }
    }

    // MARK: - Helpers

    /// Convert a tool descriptor into a human-readable display name.
    ///
    /// Prefers the ``MCPToolDescriptor/title`` if set, otherwise
    /// converts the snake_case name to Title Case.
    private func displayName(for tool: MCPToolDescriptor) -> String {
        if let title = tool.title { return title }
        return tool.name
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
