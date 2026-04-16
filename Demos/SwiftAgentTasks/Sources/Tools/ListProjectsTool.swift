import Foundation
import SwiftAgent

/// Agent tool that lists all projects with their task counts.
///
/// Returns a summary of every project including its name, color, and
/// the number of incomplete tasks assigned to it. This is a read-only
/// operation.
@AgentTool("List all projects with their incomplete task counts")
struct ListProjectsTool {
    func perform() async throws -> String {
        let projects = try await TaskStore.shared.listProjects()

        if projects.isEmpty {
            return "No projects found."
        }

        var lines: [String] = []
        for project in projects {
            let count = try await TaskStore.shared.taskCount(for: project.name)
            lines.append("\(project.name) (\(project.color)) - \(count) task(s)")
        }
        return "Found \(projects.count) project(s):\n" + lines.joined(separator: "\n")
    }
}
