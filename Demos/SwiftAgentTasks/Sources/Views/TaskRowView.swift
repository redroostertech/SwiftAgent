import SwiftUI

/// A single task row displaying a completion checkbox, title, priority
/// indicator, and optional due date badge.
///
/// Tapping the checkbox toggles the task's completion state via the
/// shared ``TaskStore``.
struct TaskRowView: View {
    /// The task to display.
    let task: TaskItem

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(spacing: 12) {
            // Completion checkbox
            Button {
                toggleCompletion()
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? .green : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            // Title
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)

                if !task.notes.isEmpty {
                    Text(task.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Priority dot
            Circle()
                .fill(priorityColor)
                .frame(width: 8, height: 8)

            // Due date badge
            if let dueDate = task.dueDate {
                Text(dueDate, style: .date)
                    .font(.caption2)
                    .foregroundStyle(dueDateColor(dueDate))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        dueDateColor(dueDate).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    /// Color for the priority indicator dot.
    private var priorityColor: Color {
        switch task.priority {
        case "high": return .red
        case "medium": return .orange
        case "low": return .blue
        default: return .gray
        }
    }

    /// Color for the due date badge, red if overdue.
    private func dueDateColor(_ date: Date) -> Color {
        if date < Date() && !task.isCompleted {
            return .red
        }
        return .secondary
    }

    /// Toggle the task's completion state.
    private func toggleCompletion() {
        if task.completedAt != nil {
            task.completedAt = nil
        } else {
            task.completedAt = Date()
        }
        task.updatedAt = Date()
        try? modelContext.save()
    }
}
