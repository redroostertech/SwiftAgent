import Foundation
import SwiftData

/// A project grouping for tasks, persisted via SwiftData.
///
/// Projects provide organizational structure for tasks. Each project has
/// a unique name and an associated color string used for UI theming.
/// Default projects ("Inbox", "Work", "Personal") are seeded on first launch.
@Model
final class Project {
    /// Stable identifier exposed as a plain string.
    var id: String

    /// The project's display name. Must be unique across all projects.
    var name: String

    /// A color identifier string used for UI theming (e.g. "blue", "green", "orange").
    var color: String

    /// Create a new project with the given properties.
    ///
    /// - Parameters:
    ///   - name: The project's display name.
    ///   - color: A color identifier string. Defaults to "blue".
    init(name: String, color: String = "blue") {
        self.id = UUID().uuidString
        self.name = name
        self.color = color
    }
}
