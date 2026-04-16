import SwiftUI

/// Renders a markdown string with proper block-level formatting.
///
/// SwiftUI's `Text` with `AttributedString(markdown:)` collapses
/// block structure (headers, paragraphs, lists) into a single run.
/// `MarkdownView` splits the source into blocks and renders each
/// one as a separate `Text` view with appropriate font styling
/// and spacing.
struct MarkdownView: View {
    /// The raw markdown source text.
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                renderBlock(block)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .textSelection(.enabled)
    }

    /// Parsed block elements from the source text.
    private var blocks: [MarkdownBlock] {
        parseBlocks(from: text)
    }

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block.kind {
        case .h1:
            Text(inlineMarkdown(block.content))
                .font(.title.bold())
        case .h2:
            Text(inlineMarkdown(block.content))
                .font(.title2.bold())
        case .h3:
            Text(inlineMarkdown(block.content))
                .font(.title3.bold())
        case .h4:
            Text(inlineMarkdown(block.content))
                .font(.headline)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\u{2022}")
                Text(inlineMarkdown(block.content))
            }
        case .numbered(let n):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(n).")
                    .monospacedDigit()
                Text(inlineMarkdown(block.content))
            }
        case .checkbox(let checked):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(checked ? .green : .secondary)
                Text(inlineMarkdown(block.content))
            }
        case .codeBlock:
            Text(block.content)
                .font(.system(.body, design: .monospaced))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        case .blockquote:
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 3)
                Text(inlineMarkdown(block.content))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 10)
            }
        case .horizontalRule:
            Divider()
        case .paragraph:
            Text(inlineMarkdown(block.content))
        case .empty:
            EmptyView()
        }
    }

    /// Parse inline markdown (bold, italic, code, links) into an
    /// AttributedString for rendering within a Text view.
    private func inlineMarkdown(_ source: String) -> AttributedString {
        (try? AttributedString(markdown: source, options: .init(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        ))) ?? AttributedString(source)
    }
}

// MARK: - Block parsing

private enum BlockKind: Equatable {
    case h1, h2, h3, h4
    case paragraph
    case bullet
    case numbered(Int)
    case checkbox(Bool)
    case codeBlock
    case blockquote
    case horizontalRule
    case empty
}

private struct MarkdownBlock {
    let kind: BlockKind
    let content: String
}

/// Split raw markdown text into block elements by line analysis.
private func parseBlocks(from text: String) -> [MarkdownBlock] {
    let lines = text.components(separatedBy: "\n")
    var blocks: [MarkdownBlock] = []
    var inCodeBlock = false
    var codeLines: [String] = []

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Code fence toggle
        if trimmed.hasPrefix("```") {
            if inCodeBlock {
                blocks.append(MarkdownBlock(kind: .codeBlock, content: codeLines.joined(separator: "\n")))
                codeLines = []
                inCodeBlock = false
            } else {
                inCodeBlock = true
            }
            continue
        }

        if inCodeBlock {
            codeLines.append(line)
            continue
        }

        // Empty line
        if trimmed.isEmpty {
            blocks.append(MarkdownBlock(kind: .empty, content: ""))
            continue
        }

        // Horizontal rule
        if trimmed == "---" || trimmed == "***" || trimmed == "___" {
            blocks.append(MarkdownBlock(kind: .horizontalRule, content: ""))
            continue
        }

        // Headers
        if trimmed.hasPrefix("#### ") {
            blocks.append(MarkdownBlock(kind: .h4, content: String(trimmed.dropFirst(5))))
            continue
        }
        if trimmed.hasPrefix("### ") {
            blocks.append(MarkdownBlock(kind: .h3, content: String(trimmed.dropFirst(4))))
            continue
        }
        if trimmed.hasPrefix("## ") {
            blocks.append(MarkdownBlock(kind: .h2, content: String(trimmed.dropFirst(3))))
            continue
        }
        if trimmed.hasPrefix("# ") {
            blocks.append(MarkdownBlock(kind: .h1, content: String(trimmed.dropFirst(2))))
            continue
        }

        // Checkboxes
        if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
            blocks.append(MarkdownBlock(kind: .checkbox(true), content: String(trimmed.dropFirst(6))))
            continue
        }
        if trimmed.hasPrefix("- [ ] ") {
            blocks.append(MarkdownBlock(kind: .checkbox(false), content: String(trimmed.dropFirst(6))))
            continue
        }

        // Bullet lists
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            blocks.append(MarkdownBlock(kind: .bullet, content: String(trimmed.dropFirst(2))))
            continue
        }

        // Numbered lists
        if let match = trimmed.firstMatch(of: /^(\d+)\.\s+(.*)$/) {
            let number = Int(match.output.1) ?? 1
            let content = String(match.output.2)
            blocks.append(MarkdownBlock(kind: .numbered(number), content: content))
            continue
        }

        // Blockquotes
        if trimmed.hasPrefix("> ") {
            blocks.append(MarkdownBlock(kind: .blockquote, content: String(trimmed.dropFirst(2))))
            continue
        }

        // Paragraph (default)
        blocks.append(MarkdownBlock(kind: .paragraph, content: trimmed))
    }

    // Close unclosed code block
    if inCodeBlock && !codeLines.isEmpty {
        blocks.append(MarkdownBlock(kind: .codeBlock, content: codeLines.joined(separator: "\n")))
    }

    return blocks
}
