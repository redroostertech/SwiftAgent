import Foundation

extension JSONEncoder {
    /// The canonical encoder used by SwiftAgent when producing wire payloads.
    ///
    /// Configured for deterministic output: keys are sorted, slashes are not
    /// escaped (smaller payloads, matches MCP reference implementations),
    /// and dates use ISO-8601 so clients in any language decode them
    /// without ambiguity.
    public static let swiftAgent: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    /// The canonical decoder used by SwiftAgent when parsing wire payloads.
    /// Mirrors ``JSONEncoder/swiftAgent`` — ISO-8601 dates, default leniency.
    public static let swiftAgent: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
