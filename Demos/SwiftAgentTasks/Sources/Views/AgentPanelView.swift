import SwiftUI
import SwiftAgent

/// The agent tool panel showing both local and remote tools.
///
/// Divided into two sections:
/// 1. **Local Tools** from the in-process agent server (system icon).
/// 2. **Remote Tools** from a connected external MCP server (cloud icon).
///
/// Selecting a tool presents an auto-generated form based on the tool's
/// input schema. The user fills in arguments and invokes the tool, with
/// results displayed inline.
struct AgentPanelView: View {
    @Environment(TaskAgentManager.self) private var agentManager

    /// The currently selected tool, if any.
    @State private var selectedTool: SelectedTool?

    /// Argument values keyed by parameter name.
    @State private var arguments: [String: String] = [:]

    /// The result string from the most recent invocation.
    @State private var result: String?

    /// Whether a tool invocation is in progress.
    @State private var isInvoking = false

    /// Error message from the most recent failed invocation.
    @State private var invokeError: String?

    var body: some View {
        List {
            // Local Tools section
            Section {
                if agentManager.localTools.isEmpty {
                    Text("Loading tools...")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(agentManager.localTools, id: \.name) { tool in
                        toolButton(tool: tool, isRemote: false)
                    }
                }
            } header: {
                Label("Local Tools", systemImage: "cpu")
            }

            // Remote Tools section
            Section {
                if agentManager.isRemoteConnected {
                    if agentManager.remoteTools.isEmpty {
                        Text("No remote tools available.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(agentManager.remoteTools, id: \.name) { tool in
                            toolButton(tool: tool, isRemote: true)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No remote server connected.")
                            .foregroundStyle(.secondary)
                        Text("Open Settings to connect to an MCP server.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            } header: {
                Label("Remote Tools", systemImage: "cloud")
            }

            // Tool form and result section
            if let selected = selectedTool {
                toolFormSection(selected: selected)
            }
        }
    }

    // MARK: - Subviews

    /// A button row for a single tool.
    private func toolButton(tool: MCPToolDescriptor, isRemote: Bool) -> some View {
        Button {
            selectTool(tool: tool, isRemote: isRemote)
        } label: {
            HStack {
                Image(systemName: isRemote ? "cloud.fill" : "cpu")
                    .foregroundStyle(isRemote ? .blue : .green)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName(for: tool))
                        .fontWeight(.medium)
                    Text(tool.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                if selectedTool?.descriptor.name == tool.name &&
                    selectedTool?.isRemote == isRemote {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
            }
        }
        .tint(.primary)
    }

    /// The form section for the selected tool's parameters and invocation.
    @ViewBuilder
    private func toolFormSection(selected: SelectedTool) -> some View {
        Section {
            // Parameter fields
            let properties = sortedProperties(for: selected.descriptor)
            if properties.isEmpty {
                Text("This tool takes no arguments.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(properties, id: \.key) { key, schema in
                    parameterField(name: key, schema: schema, descriptor: selected.descriptor)
                }
            }

            // Invoke button
            Button {
                invoke(selected: selected)
            } label: {
                HStack {
                    Spacer()
                    if isInvoking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Invoke")
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
            }
            .disabled(isInvoking)
        } header: {
            Text(displayName(for: selected.descriptor))
        }

        // Result section
        if let result {
            Section("Result") {
                Text(result)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
        }

        if let error = invokeError {
            Section("Error") {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.system(.body, design: .monospaced))
            }
        }
    }

    /// A single parameter input field, auto-generated from the schema.
    private func parameterField(name: String, schema: MCPSchema, descriptor: MCPToolDescriptor) -> some View {
        let isRequired = descriptor.inputSchema.required?.contains(name) ?? false
        let label = name.replacingOccurrences(of: "_", with: " ").capitalized
        let description = schema.description ?? ""

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .fontWeight(.medium)
                if isRequired {
                    Text("*")
                        .foregroundStyle(.red)
                }
            }

            if !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if schema.type == .boolean {
                Toggle(label, isOn: Binding(
                    get: { arguments[name]?.lowercased() == "true" },
                    set: { arguments[name] = $0 ? "true" : "false" }
                ))
                .labelsHidden()
            } else if let enumValues = schema.enumValues {
                let options = enumValues.compactMap(\.stringValue)
                Picker(label, selection: Binding(
                    get: { arguments[name] ?? options.first ?? "" },
                    set: { arguments[name] = $0 }
                )) {
                    ForEach(options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .labelsHidden()
            } else {
                TextField(description.isEmpty ? label : description, text: Binding(
                    get: { arguments[name] ?? "" },
                    set: { arguments[name] = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Actions

    /// Select a tool and reset the form.
    private func selectTool(tool: MCPToolDescriptor, isRemote: Bool) {
        selectedTool = SelectedTool(descriptor: tool, isRemote: isRemote)
        arguments = [:]
        result = nil
        invokeError = nil

        // Pre-populate defaults from schema.
        if let properties = tool.inputSchema.properties {
            for (key, schema) in properties {
                if let defaultValue = schema.defaultValue {
                    switch defaultValue {
                    case .string(let s): arguments[key] = s
                    case .bool(let b): arguments[key] = b ? "true" : "false"
                    case .int(let i): arguments[key] = "\(i)"
                    case .double(let d): arguments[key] = "\(d)"
                    default: break
                    }
                }
            }
        }
    }

    /// Invoke the selected tool with the current arguments.
    private func invoke(selected: SelectedTool) {
        isInvoking = true
        result = nil
        invokeError = nil

        // Filter out empty optional arguments.
        let requiredKeys = Set(selected.descriptor.inputSchema.required ?? [])
        var cleanedArgs = arguments
        for (key, value) in cleanedArgs {
            if value.isEmpty && !requiredKeys.contains(key) {
                cleanedArgs.removeValue(forKey: key)
            }
        }

        Task {
            do {
                let output: String
                if selected.isRemote {
                    output = try await agentManager.invokeRemoteTool(
                        name: selected.descriptor.name,
                        arguments: cleanedArgs
                    )
                } else {
                    output = try await agentManager.invokeLocalTool(
                        name: selected.descriptor.name,
                        arguments: cleanedArgs
                    )
                }
                await MainActor.run {
                    self.result = output
                    self.isInvoking = false
                }
            } catch {
                await MainActor.run {
                    self.invokeError = error.localizedDescription
                    self.isInvoking = false
                }
            }
        }
    }

    // MARK: - Helpers

    /// Convert a tool name to a human-readable display name.
    private func displayName(for tool: MCPToolDescriptor) -> String {
        if let title = tool.title, !title.isEmpty {
            return title
        }
        return tool.name
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    /// Extract and sort properties from the tool's input schema.
    private func sortedProperties(for descriptor: MCPToolDescriptor) -> [(key: String, value: MCPSchema)] {
        guard let properties = descriptor.inputSchema.properties else { return [] }
        let required = Set(descriptor.inputSchema.required ?? [])
        return properties.sorted { a, b in
            let aReq = required.contains(a.key)
            let bReq = required.contains(b.key)
            if aReq != bReq { return aReq }
            return a.key < b.key
        }
    }
}

/// Identifies a selected tool and whether it came from a remote server.
private struct SelectedTool {
    /// The tool's descriptor with schema and metadata.
    let descriptor: MCPToolDescriptor

    /// `true` if this tool came from a remote MCP server.
    let isRemote: Bool
}
