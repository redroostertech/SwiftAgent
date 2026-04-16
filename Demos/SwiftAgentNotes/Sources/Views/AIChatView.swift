import SwiftUI

/// Chat interface where the user talks to Qwen and the LLM calls
/// SwiftAgent tools to manage notes.
///
/// Type "Create a note about grocery shopping" and Qwen calls
/// `create_note_tool`. Ask "What notes do I have?" and it calls
/// `list_notes_tool`. The full agentic loop runs transparently.
struct AIChatView: View {
    @Environment(NoteAgentManager.self) private var manager

    @State private var inputText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Chat messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(manager.chatMessages) { bubble in
                            ChatBubbleView(bubble: bubble)
                                .id(bubble.id)
                        }

                        if manager.isChatting {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Thinking...")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                            .padding(.horizontal)
                            .id("loading")
                        }
                    }
                    .padding()
                }
                .onChange(of: manager.chatMessages.count) { _, _ in
                    withAnimation {
                        if let lastID = manager.chatMessages.last?.id {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        } else {
                            proxy.scrollTo("loading", anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input bar
            HStack(spacing: 12) {
                TextField("Ask about your notes...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($isFocused)
                    .submitLabel(.send)
                    .onSubmit { sendMessage() }

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || manager.isChatting)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    manager.clearChat()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(manager.chatMessages.isEmpty)
            }
        }
        .onAppear {
            manager.showWelcomeIfNeeded()
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""
        isFocused = false
        Task { await manager.chat(prompt: text) }
    }
}

/// Renders a single chat bubble with role-appropriate styling.
private struct ChatBubbleView: View {
    let bubble: ChatBubble

    var body: some View {
        HStack {
            if bubble.role == .user { Spacer(minLength: 60) }

            VStack(alignment: bubble.role == .user ? .trailing : .leading, spacing: 4) {
                Text(bubble.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(backgroundColor)
                    .foregroundStyle(foregroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                if let signature = bubble.signature {
                    Text(signature)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }

            if bubble.role != .user { Spacer(minLength: 60) }
        }
    }

    private var backgroundColor: Color {
        switch bubble.role {
        case .user: return .blue
        case .assistant: return Color(.systemGray5)
        case .tool: return Color(.systemGray6)
        case .system: return Color(.systemGray6)
        }
    }

    private var foregroundColor: Color {
        switch bubble.role {
        case .user: return .white
        default: return .primary
        }
    }
}
