import Foundation
import HuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

enum LocalModelServiceError: LocalizedError, Sendable {
    case downloadFailed(String)
    case loadFailed(String)
    case notDownloaded(String)
    case invalidRepositoryID(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let details):
            "Could not download the model. \(details)"
        case .loadFailed(let details):
            "Could not load the model. \(details)"
        case .notDownloaded(let name):
            "\(name) is not downloaded yet. Open Local Models to download it."
        case .invalidRepositoryID(let id):
            "Invalid Hugging Face repository ID: '\(id)'. Expected format 'namespace/name'."
        }
    }
}

/// Adapters that replace the `MLXHuggingFace` macros (this Xcode build does not
/// support the macro compiler plugin reliably), wiring `HubClient` downloads
/// and `swift-transformers` tokenizers into `MLXLMCommon`.
private struct HubBridge: MLXLMCommon.Downloader {
    private let upstream: HuggingFace.HubClient

    init(_ upstream: HuggingFace.HubClient) {
        self.upstream = upstream
    }

    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Foundation.Progress) -> Void
    ) async throws -> URL {
        guard let repoID = HuggingFace.Repo.ID(rawValue: id) else {
            throw LocalModelServiceError.invalidRepositoryID(id)
        }
        let revision = revision ?? "main"
        let url = try await upstream.downloadSnapshot(
            of: repoID,
            revision: revision,
            matching: patterns,
            progressHandler: { @MainActor progress in
                progressHandler(progress)
            }
        )
        LocalModelDownloadStore.record(repositoryID: id, snapshotPath: url.path)
        return url
    }
}

private struct TokenizerBridge: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}

private struct TransformersLoader: MLXLMCommon.TokenizerLoader {
    init() {}

    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await Tokenizers.AutoTokenizer.from(modelFolder: directory)
        return TokenizerBridge(upstream)
    }
}

/// MLX-backed chat generation with one persistent session per conversation.
///
/// A `ChatSession` retains its KV cache across turns. The app hands it each
/// turn's new messages only; the session accumulates its own transcript.
/// Tool-result turns continue the same session.
///
/// Best delivered through `AsyncThrowingStream` so the caller (on the main
/// actor) can iterate without `@Sendable` captures of SwiftData objects.
@MainActor
final class LocalModelService {
    static let shared = LocalModelService()

    private var containers: [String: ModelContainer] = [:]
    /// One session per conversation ID + model ID.
    private var sessions: [String: ChatSession] = [:]
    /// How many persisted messages each session has already consumed.
    private var fedCounts: [String: Int] = [:]

    private var downloader: any MLXLMCommon.Downloader { HubBridge(HuggingFace.HubClient()) }
    private var tokenizerLoader: any MLXLMCommon.TokenizerLoader { TransformersLoader() }

    private func sessionKey(modelID: String, conversationID: UUID) -> String {
        "\(modelID)::\(conversationID.uuidString)"
    }

    /// Drop cached sessions and containers. Stored model files remain.
    func unloadAll() {
        sessions.removeAll()
        containers.removeAll()
        fedCounts.removeAll()
    }

    /// Downloads the model when necessary and loads it for inference.
    func load(model: LocalModelInfo, onProgress: ((Double) -> Void)? = nil) async throws -> ModelContainer {
        if let cached = containers[model.id] { return cached }

        let configuration: ModelConfiguration
        if let directory = model.downloadedDirectory {
            configuration = ModelConfiguration(directory: directory)
        } else {
            configuration = ModelConfiguration(id: model.repositoryID, revision: model.revision ?? "main")
        }

        do {
            let container = try await loadModelContainer(
                from: downloader,
                using: tokenizerLoader,
                configuration: configuration,
                useLatest: false
            )
            _ = onProgress
            containers[model.id] = container
            return container
        } catch {
            throw LocalModelServiceError.loadFailed(error.localizedDescription)
        }
    }

    /// Streams one chat turn as `StreamEvent`s (content, reasoning, usage,
    /// tool calls). The caller drives the loop on the main actor.
    ///
    /// `request.messages` includes the new user turn as its last element, plus
    /// all earlier persisted turns for a fresh session. On a fresh session the
    /// earlier turns become its history and only the final turn is generated
    /// against; on later turns only unseen messages are appended.
    func stream(
        _ request: ChatRequest,
        conversationID: UUID
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let container = try await load(model: request.model)
                    let all = mlxMessages(from: request.messages)
                    let key = sessionKey(modelID: request.model.id, conversationID: conversationID)

                    let tools: [ToolSpec]? = request.tools.isEmpty ? nil : request.tools.map { definition in
                        [
                            "type": "function",
                            "function": [
                                "name": definition.name,
                                "description": definition.description,
                                "parameters": sendableParameters(definition.parameters)
                            ]
                        ] as [String: any Sendable]
                    }

                    let session: ChatSession
                    let turnMessages: [Chat.Message]
                    if let existing = sessions[key] {
                        session = existing
                        let fed = fedCounts[key] ?? 0
                        turnMessages = Array(all.dropFirst(min(fed, all.count)))
                        if let tools { session.tools = tools }
                    } else {
                        let history = Array(all.dropLast())
                        session = ChatSession(
                            container,
                            instructions: request.systemPrompt,
                            history: history,
                            tools: tools
                        )
                        sessions[key] = session
                        turnMessages = Array(all.suffix(1))
                    }

                    session.generateParameters = GenerateParameters(
                        maxTokens: 2048,
                        temperature: Float(request.temperature ?? 0.6),
                        topP: 0.95
                    )

                    if !turnMessages.isEmpty {
                        for try await generation in session.streamDetails(to: turnMessages) {
                            try Task.checkCancellation()
                            switch generation {
                            case .chunk(let text):
                                if !text.isEmpty { continuation.yield(.content(text)) }
                            case .toolCall(let toolCall):
                                let call = FunctionToolCall(
                                    id: toolCall.id ?? UUID().uuidString,
                                    name: toolCall.function.name,
                                    arguments: argumentsString(toolCall.function.arguments)
                                )
                                continuation.yield(.toolCalls([call]))
                            case .info(let info):
                                continuation.yield(.usage(TokenUsage(inputTokens: info.promptTokenCount, outputTokens: info.generationTokenCount)))
                            case .rejectedToolCall:
                                break
                            @unknown default:
                                break
                            }
                        }
                        fedCounts[key] = all.count
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Continues the same session with a tool result, preserving its cache.
    func continueWithToolResult(
        conversationID: UUID,
        model: LocalModelInfo,
        toolCallID: String,
        toolName: String,
        result: String
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let key = sessionKey(modelID: model.id, conversationID: conversationID)
                    guard let session = sessions[key] else {
                        throw LocalModelServiceError.loadFailed("No active model session for this conversation.")
                    }
                    let toolMessage: Chat.Message = .tool(result, id: toolCallID, name: toolName)
                    for try await generation in session.streamDetails(to: [toolMessage]) {
                        try Task.checkCancellation()
                        switch generation {
                        case .chunk(let text):
                            if !text.isEmpty { continuation.yield(.content(text)) }
                        case .toolCall(let toolCall):
                            let call = FunctionToolCall(
                                id: toolCall.id ?? UUID().uuidString,
                                name: toolCall.function.name,
                                arguments: argumentsString(toolCall.function.arguments)
                            )
                            continuation.yield(.toolCalls([call]))
                        case .info(let info):
                            continuation.yield(.usage(TokenUsage(inputTokens: info.promptTokenCount, outputTokens: info.generationTokenCount)))
                        case .rejectedToolCall:
                            break
                        @unknown default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Conversions

    private func mlxMessages(from messages: [WireMessage]) -> [Chat.Message] {
        messages.map { message in
            switch message.role {
            case .user:
                return .user(message.content)
            case .assistant:
                return .assistant(message.content)
            case .system:
                return .system(message.content)
            case .tool:
                return .tool(message.content, id: message.toolCallID, name: message.toolName)
            }
        }
    }

    private func argumentsString(_ value: [String: MLXLMCommon.JSONValue]) -> String {
        let json = value.mapValues { jsonValueToAny($0) }
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }

    private func jsonValueToAny(_ value: MLXLMCommon.JSONValue) -> Any {
        switch value {
        case .null: return NSNull()
        case .bool(let b): return b
        case .int(let n): return n
        case .double(let d): return d
        case .string(let s): return s
        case .array(let items): return items.map { jsonValueToAny($0) }
        case .object(let dict): return dict.mapValues { jsonValueToAny($0) }
        }
    }

    private func sendableParameters(_ value: JSONValue) -> any Sendable {
        switch value {
        case .object(let dict):
            let mapped = dict.mapValues { sendableParameters($0) }
            return mapped as [String: any Sendable]
        case .array(let items):
            return items.map { sendableParameters($0) } as [any Sendable]
        case .string(let s): return s
        case .int(let n): return n
        case .double(let d): return d
        case .bool(let b): return b
        case .null: return NSNull()
        }
    }
}
