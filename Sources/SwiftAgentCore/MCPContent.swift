import Foundation

/// A content block returned from a tool call.
///
/// Tools return an ordered list of content blocks so a single call can
/// yield mixed media — for example, a sentence of human-readable text
/// followed by an inline image thumbnail. SwiftAgent currently supports:
///
/// - ``text(_:)`` — plain human-readable text.
/// - ``json(_:)`` — structured JSON the caller can parse directly. Prefer
///   this over stringified JSON embedded in `.text`.
/// - ``image(data:mimeType:)`` — inline binary image data, base64 on the wire.
/// - ``resource(uri:mimeType:)`` — reference to a resource the client can
///   fetch separately via `resources/read`, avoiding duplication.
public enum MCPContent: Sendable, Hashable, Codable {
    /// Plain human-readable text.
    case text(String)
    /// Structured JSON data (no stringification).
    case json(JSONValue)
    /// Inline binary image data with a MIME type such as `"image/png"`.
    case image(data: Data, mimeType: String)
    /// Reference to a resource fetched separately via `resources/read`.
    case resource(uri: String, mimeType: String?)

    private enum CodingKeys: String, CodingKey {
        case type, text, data, mimeType, uri
    }

    private enum ContentType: String, Codable {
        case text, json, image, resource
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ContentType.self, forKey: .type)
        switch type {
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        case .json:
            self = .json(try container.decode(JSONValue.self, forKey: .data))
        case .image:
            let base64 = try container.decode(String.self, forKey: .data)
            guard let data = Data(base64Encoded: base64) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .data, in: container,
                    debugDescription: "Image data was not valid base64."
                )
            }
            let mime = try container.decode(String.self, forKey: .mimeType)
            self = .image(data: data, mimeType: mime)
        case .resource:
            let uri = try container.decode(String.self, forKey: .uri)
            let mime = try container.decodeIfPresent(String.self, forKey: .mimeType)
            self = .resource(uri: uri, mimeType: mime)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode(ContentType.text, forKey: .type)
            try container.encode(text, forKey: .text)
        case .json(let value):
            try container.encode(ContentType.json, forKey: .type)
            try container.encode(value, forKey: .data)
        case .image(let data, let mime):
            try container.encode(ContentType.image, forKey: .type)
            try container.encode(data.base64EncodedString(), forKey: .data)
            try container.encode(mime, forKey: .mimeType)
        case .resource(let uri, let mime):
            try container.encode(ContentType.resource, forKey: .type)
            try container.encode(uri, forKey: .uri)
            try container.encodeIfPresent(mime, forKey: .mimeType)
        }
    }
}
