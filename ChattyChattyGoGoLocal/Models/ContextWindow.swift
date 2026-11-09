import Foundation

/// Roughly how many tokens a string takes, using the usual characters-per-token rule.
extension String {
    static func estimateTokens(in text: String) -> Int {
        Int((Double(text.count) / 4).rounded(.up))
    }
}

/// Kept for call sites that used to address the estimator on `ModelInfo`.
typealias TokenEstimator = String

/// Context-window assumptions for local models.
enum LocalModelContext {
    static let defaultContextLimit = 32_000
    /// Certain prompts from some tool calls are illustrative; see the preset rows
    /// in `LocalModelCatalog` for the authoritative list.
    static let contextLimits: [String: Int] = [
        "qwen3-0.6b-mlx-4bit": 32_768,
        "qwen3-1.7b-mlx-4bit": 32_768,
        "gemma-3-1b-it-mlx-4bit": 32_768,
        "qwen2.5-3b-instruct-mlx-4bit": 32_768,
        "llama-3.2-3b-instruct-mlx-4bit": 131_072,
        "qwen3-4b-mlx-4bit": 32_768,
        "lamma-3.1-8b-instruct-mlx-4bit": 131_072,
        "hermes-3-llama-3.1-8b-mlx-4bit": 131_072
    ]

    static func contextLimit(for modelID: String) -> Int {
        contextLimits[modelID] ?? defaultContextLimit
    }
}

/// Decides which part of a conversation is sent to the model.
enum ContextWindow {
    /// Tokens reserved for the answer, so the request does not fill the window.
    static let outputReserve = 4_096
    /// Never trim below this many messages, even if the window is full.
    static let minimumKeptMessages = 4

    struct Result: Sendable, Equatable {
        let kept: [WireMessage]
        let trimmed: Int
        /// Rough token count of the request that would actually be sent.
        let estimatedTokens: Int
    }

    /// Keeps the newest messages that fit the model's context window.
    ///
    /// The system prompt is not part of the list; the caller sends it separately and it
    /// is accounted for here.
    static func fit(
        _ messages: [WireMessage],
        systemPrompt: String?,
        modelID: String
    ) -> Result {
        let budget = max(1_000, LocalModelContext.contextLimit(for: modelID) - outputReserve)
        var used = String.estimateTokens(in: systemPrompt ?? "")

        var kept: [WireMessage] = []
        var index = messages.count - 1
        while index >= 0 {
            let message = messages[index]
            let cost = String.estimateTokens(in: message.content) + 8
            if used + cost > budget, kept.count >= minimumKeptMessages {
                break
            }
            kept.append(message)
            used += cost
            index -= 1
        }
        kept.reverse()

        return Result(
            kept: kept,
            trimmed: index + 1,
            estimatedTokens: used
        )
    }
}
