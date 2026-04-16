import Foundation
import NaturalLanguage

/// On-device semantic embedding service using Apple's NaturalLanguage
/// framework.
///
/// `EmbeddingService` wraps `NLEmbedding.sentenceEmbedding` to
/// compute dense vector representations of text. These vectors enable:
///
/// - **Semantic search** — "find notes about food" matches a note
///   titled "Grocery List" even though the words don't overlap.
/// - **Auto-linking** — notes with high cosine similarity are
///   suggested as related.
/// - **Clustering** — group similar notes without manual tagging.
///
/// All computation happens on-device with no network calls. The
/// embedding model is bundled with iOS for English.
final class EmbeddingService: Sendable {
    /// Shared instance.
    static let shared = EmbeddingService()

    /// The NLEmbedding model, loaded once.
    private let model: NLEmbedding?

    private init() {
        self.model = NLEmbedding.sentenceEmbedding(for: .english)
    }

    /// Whether the embedding model is available on this device.
    var isAvailable: Bool { model != nil }

    /// Compute a semantic embedding vector for the given text.
    ///
    /// Combines the title and body into a single string before
    /// embedding so the vector captures the full note context.
    ///
    /// - Parameter text: The text to embed.
    /// - Returns: A dense vector (typically 512 dimensions), or `nil`
    ///   if the model is unavailable.
    func embed(_ text: String) -> [Double]? {
        guard let model else { return nil }
        return model.vector(for: text)
    }

    /// Compute an embedding for a note's combined title and body.
    ///
    /// - Parameters:
    ///   - title: The note's title.
    ///   - body: The note's body.
    /// - Returns: The embedding vector, or `nil` if unavailable.
    func embedNote(title: String, body: String) -> [Double]? {
        embed("\(title). \(body)")
    }

    /// Compute cosine similarity between two embedding vectors.
    ///
    /// - Parameters:
    ///   - a: First vector.
    ///   - b: Second vector.
    /// - Returns: Similarity score in `[-1, 1]` where `1` means
    ///   identical direction.
    func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let dot = zip(a, b).map(*).reduce(0, +)
        let magA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magB = sqrt(b.map { $0 * $0 }.reduce(0, +))
        guard magA > 0, magB > 0 else { return 0 }
        return dot / (magA * magB)
    }

    /// Find notes similar to a query embedding, ranked by similarity.
    ///
    /// - Parameters:
    ///   - query: The embedding to search against.
    ///   - notes: The candidate notes (must have non-nil embeddings).
    ///   - threshold: Minimum similarity score to include. Default 0.3.
    ///   - limit: Maximum results to return. Default 5.
    /// - Returns: Notes sorted by descending similarity, above threshold.
    func findSimilar(
        to query: [Double],
        in notes: [Note],
        threshold: Double = 0.3,
        limit: Int = 5
    ) -> [(note: Note, similarity: Double)] {
        notes.compactMap { note in
            guard let emb = note.embedding else { return nil }
            let sim = cosineSimilarity(query, emb)
            return sim >= threshold ? (note, sim) : nil
        }
        .sorted { $0.similarity > $1.similarity }
        .prefix(limit)
        .map { $0 }
    }
}
