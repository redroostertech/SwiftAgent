import Foundation

/// A streaming post-processor applied to raw model output before it
/// reaches the user.
///
/// Some model families emit control text that should be swallowed
/// (Qwen3's `<think>…</think>` blocks, DeepSeek-R1's `<|reasoning|>…`,
/// etc.). These tags can straddle stream chunk boundaries — the model
/// emits one token at a time, and `<think>` is multiple tokens — so the
/// filter must buffer conservatively rather than operate chunk-by-chunk.
///
/// Semantics:
///   - `process(_:)` consumes a chunk and returns the user-visible
///     substring. Return `""` while buffering a potential tag boundary.
///   - `flush()` is called once at stream end to release any buffered
///     text that turned out to be genuine trailing output.
///
/// Filters are value types; hold as `any OutputFilter` if you need
/// runtime polymorphism.
public protocol OutputFilter: Sendable {
    mutating func process(_ chunk: String) -> String
    mutating func flush() -> String
}

/// No-op filter. Returned when a model has no quirks to strip.
public struct PassthroughOutputFilter: OutputFilter {
    public init() {}
    public mutating func process(_ chunk: String) -> String { chunk }
    public mutating func flush() -> String { "" }
}

/// Strips `<think>…</think>` blocks from a streaming response.
///
/// Qwen3 hybrid models ("thinking" + "non-thinking" in one checkpoint)
/// emit empty-or-near-empty `<think>` blocks even when the user appends
/// `/no_think`. They arrive as raw text in the output stream, not as
/// structured metadata, so they have to be filtered here.
///
/// Boundary safety: any chunk that contains `<` is held until we can
/// decide whether it's the start of an opener. Likewise, once inside a
/// think block we retain the last ~8 characters in case `</think>`
/// straddles the next chunk.
public struct ThinkTagOutputFilter: OutputFilter {
    private var insideThink = false
    private var pending = ""

    public init() {}

    public mutating func process(_ chunk: String) -> String {
        pending += chunk
        var output = ""

        while !pending.isEmpty {
            if insideThink {
                if let closeRange = pending.range(of: "</think>") {
                    pending.removeSubrange(pending.startIndex..<closeRange.upperBound)
                    insideThink = false
                } else {
                    if pending.count > 8 {
                        pending = String(pending.suffix(8))
                    }
                    return output
                }
            } else {
                if let openRange = pending.range(of: "<think>") {
                    output += pending[pending.startIndex..<openRange.lowerBound]
                    pending.removeSubrange(pending.startIndex..<openRange.upperBound)
                    insideThink = true
                } else if pending.contains("<") {
                    if let lastOpen = pending.lastIndex(of: "<") {
                        output += pending[pending.startIndex..<lastOpen]
                        pending = String(pending[lastOpen...])
                    }
                    return output
                } else {
                    output += pending
                    pending.removeAll(keepingCapacity: true)
                }
            }
        }
        return output
    }

    public mutating func flush() -> String {
        if insideThink {
            pending.removeAll()
            return ""
        }
        let tail = pending
        pending.removeAll()
        return tail
    }
}
