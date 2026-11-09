import Foundation

/// Reasoning / thinking budget requested from the model.
enum ReasoningLevel: String, CaseIterable, Identifiable, Sendable {
    case off
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .low: "Low"
        case .medium: "Balanced"
        case .high: "Deep"
        }
    }

    var symbol: String {
        switch self {
        case .off: "bolt.slash"
        case .low: "hare"
        case .medium: "gauge.with.dots.needle.33percent"
        case .high: "brain.head.profile"
        }
    }

    var explanation: String {
        switch self {
        case .off: "No extra thinking time. Fastest and cheapest."
        case .low: "A little extra reasoning for straightforward questions."
        case .medium: "Balanced thinking time for most questions."
        case .high: "Maximum reasoning budget. Slower, best for hard problems."
        }
    }
}

/// A file that travels with a user message.
enum WireAttachment: Sendable, Hashable {
    case image(mimeType: String, base64: String)
    case document(text: String)
    case video(mimeType: String, base64: String)
    case audio(mimeType: String, base64: String)

    var isImage: Bool {
        if case .image = self { return true }
        return false
    }
}

/// A function the model may ask the app to execute.
struct FunctionToolDefinition: Sendable {
    let name: String
    let description: String
    let parameters: JSONValue
}

/// A function call returned by a model.
struct FunctionToolCall: Sendable, Hashable {
    let id: String
    let name: String
    /// JSON-encoded argument object.
    let arguments: String
}

/// A message in the wire format used by the providers.
struct WireMessage: Sendable, Hashable {
    enum Role: String, Sendable {
        case user
        case assistant
        case system
        case tool
    }

    let role: Role
    let content: String
    /// Images and document text that belong to this message.
    var attachments: [WireAttachment] = []
    /// Function calls when this is an assistant tool-call message.
    var toolCalls: [FunctionToolCall] = []
    /// The call id and name when this is a tool-result message.
    var toolCallID: String? = nil
    var toolName: String? = nil
}

/// Token counts reported by the provider for one request.
struct TokenUsage: Sendable, Equatable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    /// Part of the input that was served from the provider's prompt cache.
    var cachedInputTokens: Int = 0

    var isEmpty: Bool { inputTokens == 0 && outputTokens == 0 }

    /// Input tokens that were not cached and are billed at the full rate.
    var billedInputTokens: Int { max(0, inputTokens - cachedInputTokens) }

    /// Providers report usage in pieces (Anthropic sends the input count first and the
    /// output count later), so the pieces are merged rather than replaced.
    func merged(with other: TokenUsage) -> TokenUsage {
        TokenUsage(
            inputTokens: max(inputTokens, other.inputTokens),
            outputTokens: max(outputTokens, other.outputTokens),
            cachedInputTokens: max(cachedInputTokens, other.cachedInputTokens)
        )
    }

    /// Adds usage from a separate tool round to the totals for the whole turn.
    func adding(_ other: TokenUsage) -> TokenUsage {
        TokenUsage(
            inputTokens: inputTokens + other.inputTokens,
            outputTokens: outputTokens + other.outputTokens,
            cachedInputTokens: cachedInputTokens + other.cachedInputTokens
        )
    }
}

/// One piece of streamed output.
enum StreamEvent: Sendable {
    case content(String)
    case reasoning(String)
    case usage(TokenUsage)
    case toolCalls([FunctionToolCall], usage: TokenUsage? = nil)
}

/// A local on-device model, with its source repository and storage footprint.
struct LocalModelInfo: Identifiable, Hashable, Sendable {
    let id: String
    var displayName: String
    /// Hugging Face repository ID.
    var repositoryID: String
    /// Optional revision; `main` when nil.
    var revision: String?
    /// Approximate download/storage size in bytes.
    var downloadSizeBytes: Int64
    /// Approximate runtime memory needed, in bytes.
    var runtimeMemoryEstimate: Int64
    var summary: String
    var bestFor: [String]
    var parameters: String
    /// Whether this catalogue was built for E-series chips.
    var isDeviceOptimized: Bool
    var privacyNote: String?
    /// True when local files already exist in the app sandbox.
    var isDownloaded: Bool { downloadedDirectory != nil }
    var downloadedDirectory: URL?

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useGB]
        return formatter.string(fromByteCount: downloadSizeBytes)
    }

    var formattedMemory: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useGB]
        return formatter.string(fromByteCount: runtimeMemoryEstimate)
    }

    var compatibleDevice: String {
        let deviceGiB = ProcessInfo.processInfo.physicalMemory / 1_073_741_824
        if isDeviceOptimized { return "Designed for mobile / 8 GiB-class devices" }
        if downloadSizeBytes <= 2 * 1_073_741_824 {
            return "Practical on 8 GiB-class devices • this device: \(deviceGiB) GiB"
        }
        return "May need a higher-memory Apple Silicon device • this device: \(deviceGiB) GiB"
    }

    init(
        id: String,
        displayName: String,
        repositoryID: String,
        revision: String? = nil,
        downloadSizeBytes: Int64,
        runtimeMemoryEstimate: Int64,
        summary: String,
        bestFor: [String],
        parameters: String,
        isDeviceOptimized: Bool = false,
        privacyNote: String? = nil,
        downloadedDirectory: URL? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.repositoryID = repositoryID
        self.revision = revision
        self.downloadSizeBytes = downloadSizeBytes
        self.runtimeMemoryEstimate = runtimeMemoryEstimate
        self.summary = summary
        self.bestFor = bestFor
        self.parameters = parameters
        self.isDeviceOptimized = isDeviceOptimized
        self.privacyNote = privacyNote
        self.downloadedDirectory = downloadedDirectory
    }

    var statusLabel: String {
        isDownloaded ? "On this device" : "Not downloaded"
    }
}


/// Records where Hugging Face snapshots live, keyed by repository ID,
/// so downloaded state survives across launches.
enum LocalModelDownloadStore {
    private static let key = "localModelSnapshots"

    static var snapshots: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func record(repositoryID: String, snapshotPath: String) {
        var map = snapshots
        map[repositoryID] = snapshotPath
        snapshots = map
    }

    static func snapshotURL(for repositoryID: String) -> URL? {
        guard let path = snapshots[repositoryID] else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        let hasWeights = (try? FileManager.default.contentsOfDirectory(atPath: path).contains { $0.hasSuffix(".safetensors") }) ?? false
        return hasWeights ? url : nil
    }

    static func remove(repositoryID: String) {
        var map = snapshots
        map.removeValue(forKey: repositoryID)
        snapshots = map
    }
}

/// Categories for local-model presets.
enum LocalModelCatalog {
    static let presetModels: [LocalModelInfo] = [
        // Tiniest tier — smoke tests and very constrained hosts.
        LocalModelInfo(
            id: "qwen3-0.6b-mlx-4bit",
            displayName: "Qwen3 0.6B 4-bit",
            repositoryID: "mlx-community/Qwen3-0.6B-4bit",
            downloadSizeBytes: 396_000_000,
            runtimeMemoryEstimate: 650_000_000,
            summary: "Tiniest reasoner; offline chat baseline (MMLU 52.8).",
            bestFor: ["Smoke tests", "Constrained hosts"],
            parameters: "0.6B",
            isDeviceOptimized: true
        ),
        LocalModelInfo(
            id: "llama-3.2-1b-instruct-mlx-4bit",
            displayName: "Llama 3.2 1B Instruct 4-bit",
            repositoryID: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            downloadSizeBytes: 724_000_000,
            runtimeMemoryEstimate: 900_000_000,
            summary: "Weakest Llama; do not expect miracles — a 128K-context curiosity (MMLU 49.3).",
            bestFor: ["Tiny hosts", "Comparison"],
            parameters: "1.2B",
            isDeviceOptimized: true
        ),
        LocalModelInfo(
            id: "gemma-3-1b-it-mlx-4bit",
            displayName: "Gemma 3 1B Instruct 4-bit",
            repositoryID: "mlx-community/gemma-3-1b-it-qat-4bit",
            downloadSizeBytes: 500_000_000,
            runtimeMemoryEstimate: 800_000_000,
            summary: "Tiny English-centric tasks (HellaSwag 62.3 10-shot).",
            bestFor: ["Quick answers"],
            parameters: "1B",
            isDeviceOptimized: true
        ),
        LocalModelInfo(
            id: "deepseek-r1-distill-qwen-1.5b-mlx-4bit",
            displayName: "DeepSeek R1 Distill Qwen 1.5B 4-bit",
            repositoryID: "mlx-community/DeepSeek-R1-Distill-Qwen-1.5B-4bit",
            downloadSizeBytes: 950_000_000,
            runtimeMemoryEstimate: 1_150_000_000,
            summary: "Long chain-of-thought at 0.8 GB; no thinking toggle (AIME'24 28.9).",
            bestFor: ["Reasoning", "Maths"],
            parameters: "1.5B",
            isDeviceOptimized: true
        ),
        LocalModelInfo(
            id: "lfm2-1.2b-mlx-4bit",
            displayName: "LFM2 1.2B 4-bit",
            repositoryID: "mlx-community/LFM2-1.2B-4bit",
            downloadSizeBytes: 700_000_000,
            runtimeMemoryEstimate: 900_000_000,
            summary: "Liquid AI edge model with first-class tool calling — the Liquid pick that runs in MLX today.",
            bestFor: ["Tool use", "Agents", "Tiny hosts"],
            parameters: "1.2B",
            isDeviceOptimized: true
        ),
        // Small chat tier — the practical 8 GiB sweet spot.
        LocalModelInfo(
            id: "qwen3-1.7b-mlx-4bit",
            displayName: "Qwen3 1.7B 4-bit",
            repositoryID: "mlx-community/Qwen3-1.7B-4bit",
            downloadSizeBytes: 900_000_000,
            runtimeMemoryEstimate: 1_350_000_000,
            summary: "Small reasoner; on-device chat (MMLU 62.6).",
            bestFor: ["Everyday questions", "Tiny constrained hosts"],
            parameters: "1.7B",
            isDeviceOptimized: true
        ),
        LocalModelInfo(
            id: "smollm3-3b-mlx-4bit",
            displayName: "SmolLM3 3B 4-bit",
            repositoryID: "mlx-community/SmolLM3-3B-4bit",
            downloadSizeBytes: 1_700_000_000,
            runtimeMemoryEstimate: 2_100_000_000,
            summary: "Reasoning and no-think chat in one model (AIME'25 36.7).",
            bestFor: ["General assistance", "Reasoning"],
            parameters: "3B",
            isDeviceOptimized: true
        ),
        LocalModelInfo(
            id: "qwen2.5-3b-instruct-mlx-4bit",
            displayName: "Qwen2.5 3B Instruct 4-bit",
            repositoryID: "mlx-community/Qwen2.5-3B-Instruct-4bit",
            downloadSizeBytes: 1_800_000_000,
            runtimeMemoryEstimate: 2_200_000_000,
            summary: "A practical middle ground between the tiniest models and better desktop-class reasoning.",
            bestFor: ["General assistance", "Summaries"],
            parameters: "3B",
            isDeviceOptimized: true
        ),
        LocalModelInfo(
            id: "llama-3.2-3b-instruct-mlx-4bit",
            displayName: "Llama 3.2 3B Instruct 4-bit",
            repositoryID: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            downloadSizeBytes: 1_800_000_000,
            runtimeMemoryEstimate: 2_150_000_000,
            summary: "Safe cross-hardware default; 128K context (MMLU 63.4).",
            bestFor: ["General assistance", "Compact host testing"],
            parameters: "3.2B",
            isDeviceOptimized: true
        ),
        LocalModelInfo(
            id: "phi-4-mini-instruct-mlx-4bit",
            displayName: "Phi-4-mini Instruct 4-bit",
            repositoryID: "mlx-community/Phi-4-mini-instruct-4bit",
            downloadSizeBytes: 2_100_000_000,
            runtimeMemoryEstimate: 2_500_000_000,
            summary: "Strong bench-per-GB; English-first (MMLU 67.3).",
            bestFor: ["General assistance", "English tasks"],
            parameters: "3.8B",
            isDeviceOptimized: true
        ),
        LocalModelInfo(
            id: "phi-4-mini-reasoning-mlx-4bit",
            displayName: "Phi-4-mini Reasoning 4-bit",
            repositoryID: "mlx-community/Phi-4-mini-reasoning-4bit",
            downloadSizeBytes: 2_100_000_000,
            runtimeMemoryEstimate: 2_500_000_000,
            summary: "Maths-grade chain-of-thought on phone (AIME'24 57.5).",
            bestFor: ["Maths", "Reasoning"],
            parameters: "3.8B",
            isDeviceOptimized: true
        ),
        LocalModelInfo(
            id: "qwen3-4b-mlx-4bit",
            displayName: "Qwen3 4B 4-bit",
            repositoryID: "mlx-community/Qwen3-4B-4bit",
            downloadSizeBytes: 2_200_000_000,
            runtimeMemoryEstimate: 2_900_000_000,
            summary: "Best ≤4B 2025 reasoner (MMLU 73.0); 32K (128K YaRN).",
            bestFor: ["Structured answers", "Reasoning"],
            parameters: "4B",
            isDeviceOptimized: true
        ),
        // Reference tier — for measuring memory/speed on constrained hosts.
        LocalModelInfo(
            id: "llama-3.1-8b-instruct-mlx-4bit",
            displayName: "Llama 3.1 8B Instruct 4-bit",
            repositoryID: "mlx-community/Llama-3.1-8B-Instruct-4bit",
            downloadSizeBytes: 4_500_000_000,
            runtimeMemoryEstimate: 5_200_000_000,
            summary: "Larger reference point for memory and speed measurements on constrained devices.",
            bestFor: ["Benchmarking", "Local evaluation"],
            parameters: "8B"
        ),
        LocalModelInfo(
            id: "hermes-3-llama-3.1-8b-mlx-4bit",
            displayName: "Hermes 3 Llama 3.1 8B 4-bit",
            repositoryID: "mlx-community/Hermes-3-Llama-3.1-8B-4bit",
            downloadSizeBytes: 4_700_000_000,
            runtimeMemoryEstimate: 5_400_000_000,
            summary: "Instruction-tuned Llama 3.1 variant for comparing local model quality at 8B.",
            bestFor: ["Evaluation", "Instruction following"],
            parameters: "8B"
        )
    ]


    static func installedModelURLs() -> [URL] {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).map {
            $0.appendingPathComponent("LocalModels", isDirectory: true)
        }
    }

    static var localModelsDirectory: URL { installedModelURLs()[0] }

    static func withDownloadedPaths(_ models: [LocalModelInfo]) -> [LocalModelInfo] {
        let base = localModelsDirectory
        return models.map { model in
            let candidate = base.appendingPathComponent(model.id, isDirectory: true)
            let hasWeights = (try? FileManager.default.contentsOfDirectory(atPath: candidate.path).contains { $0.hasSuffix(".safetensors") }) ?? false
            var copy = model
            if hasWeights {
                copy.downloadedDirectory = candidate
            } else if let snapshot = LocalModelDownloadStore.snapshotURL(for: model.repositoryID) {
                copy.downloadedDirectory = snapshot
            } else {
                copy.downloadedDirectory = nil
            }
            return copy
        }
    }

    /// Fast-local presets suitable for devices with around 8 GiB or more.
    static func deviceFriendlyModels() -> [LocalModelInfo] {
        withDownloadedPaths(presetModels.filter { $0.isDeviceOptimized })
    }

    /// All presets.
    static func allModels() -> [LocalModelInfo] {
        withDownloadedPaths(presetModels)
    }

    /// Any other downloaded model ID whose directory does not match a preset.
    static func customInstalledModels() -> [LocalModelInfo] {
        let base = localModelsDirectory
        let presetIDs = Set(presetModels.map(\.repositoryID))
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: base.path) else { return [] }
        return entries.compactMap { entry -> LocalModelInfo? in
            let url = base.appendingPathComponent(entry, isDirectory: true)
            let files = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
            guard files.contains(where: { $0.hasSuffix(".safetensors") }) else { return nil }
            var size: Int64 = 0
            (try? FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]))?.forEach { item in
                if let itemURL = item as? URL, let v = try? itemURL.resourceValues(forKeys: [.fileSizeKey]),
                   let fileSize = v.fileSize { size += Int64(fileSize) }
            }
            let repoPart = entry.replacingOccurrences(of: "__", with: "/")
            guard !presetIDs.contains(repoPart) else { return nil }
            return LocalModelInfo(
                id: entry,
                displayName: entry.replacingOccurrences(of: "__", with: "/").components(separatedBy: "/").last ?? entry,
                repositoryID: repoPart,
                downloadSizeBytes: size,
                runtimeMemoryEstimate: max(size, 500_000_000),
                summary: "Imported from Hugging Face.",
                bestFor: ["Custom evaluation"],
                parameters: "Unknown",
                downloadedDirectory: url
            )
        }
    }
}

/// Everything needed for one local generation turn.
struct ChatRequest: Sendable {
    let model: LocalModelInfo
    let messages: [WireMessage]
    let systemPrompt: String?
    let tools: [FunctionToolDefinition]
    let temperature: Double?

    init(
        model: LocalModelInfo,
        messages: [WireMessage],
        systemPrompt: String? = nil,
        temperature: Double? = nil,
        tools: [FunctionToolDefinition] = []
    ) {
        self.model = model
        self.messages = messages
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.tools = tools
    }
}

/// Minimal, `Sendable` JSON tree so request bodies never cross actor boundaries with `Any`.
enum JSONValue: Sendable, Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() {
            self = .null
        } else if let boolean = try? value.decode(Bool.self) {
            self = .bool(boolean)
        } else if let integer = try? value.decode(Int.self) {
            self = .int(integer)
        } else if let number = try? value.decode(Double.self) {
            self = .double(number)
        } else if let string = try? value.decode(String.self) {
            self = .string(string)
        } else if let array = try? value.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? value.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(in: value, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    static func encode(_ value: JSONValue) throws -> Data {
        try JSONEncoder().encode(value)
    }

    /// Returns a copy of an object with one key replaced or added.
    func with(_ key: String, _ value: JSONValue) -> JSONValue {
        guard case .object(let existing) = self else { return self }
        var object = existing
        object[key] = value
        return .object(object)
    }
}

/// Errors surfaced to the UI.
enum APIError: LocalizedError, Sendable {
    case missingAPIKey
    case http(status: Int, body: String, retryAfter: Int?)
    case transport(String)
    case decoding(String)
    case failed(String)

    init(status: Int, body: String, retryAfter: Int? = nil) {
        self = .http(status: status, body: body, retryAfter: retryAfter)
    }

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "No API key yet. Add your OpenCode Go key in Settings."
        case .http(let status, let body, _):
            body.isEmpty ? "The server returned HTTP \(status)." : "HTTP \(status): \(Self.friendlyMessage(from: body) ?? body)"
        case .transport(let message):
            message
        case .decoding(let message):
            message
        case .failed(let message):
            message
        }
    }

    /// Pulls the human readable part out of a JSON error body, for example
    /// `{"type":"error","error":{"type":"MissingSessionID","message":"…"}}`.
    static func friendlyMessage(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let error = object["error"] as? [String: Any] {
            let type = error["type"] as? String
            let message = error["message"] as? String
            switch (type, message) {
            case let (type?, message?):
                return "\(type): \(message)"
            case let (type?, nil):
                return type
            case let (nil, message?):
                return message
            default:
                break
            }
        }
        if let message = object["message"] as? String {
            return message
        }
        if let detail = object["detail"] as? String {
            return detail
        }
        return nil
    }

    /// The key was rejected.
    ///
    /// A 403 that is really about a model the account may not use (privacy
    /// restrictions, region blocks) is not an auth problem: the key itself is fine.
    var isAuthProblem: Bool {
        if case .http(let status, let body, _) = self {
            if status == 401 { return true }
            if status == 403 {
                return !body.lowercased().contains("model") && !suggestsModelUnavailable
            }
        }
        return false
    }

    /// The server's own words for an HTTP rejection, without the type prefix.
    ///
    /// Kept verbatim so the app can explain *why* a model was refused, in the
    /// gateway's phrasing.
    var serverReason: String? {
        guard case .http(_, let body, _) = self, !body.isEmpty else { return nil }
        var message: String?
        if let data = body.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any], let text = error["message"] as? String {
                message = text
            } else if let text = object["message"] as? String {
                message = text
            } else if let text = object["detail"] as? String {
                message = text
            }
        }
        if message == nil { message = Self.friendlyMessage(from: body) }
        if message == nil { message = body }
        guard var text = message, !text.isEmpty else { return nil }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > 300 { text = String(text.prefix(300)) + "…" }
        return text
    }

    /// The gateway asked us to slow down.
    var isRateLimit: Bool {
        if case .http(let status, _, _) = self, status == 429 { return true }
        return false
    }

    /// Seconds to wait before trying again, from the response header.
    var retryAfterSeconds: Int? {
        if case .http(_, _, let seconds) = self { return seconds }
        return nil
    }

    /// The account's allowance is spent, not merely busy.
    ///
    /// A 429 whose body says the usage limit is reached is final: waiting and
    /// retrying only delays the same verdict (that is how a trial run used to
    /// stretch "surprisingly long"). A plain rate-limit 429 - "slow down" - is
    /// different and stays retryable.
    var isQuotaExhausted: Bool {
        if case .http(let status, let body, _) = self, status == 429 {
            let lowered = body.lowercased()
            return lowered.contains("freeusagelimiterror")
                || lowered.contains("usage limit reached")
                || lowered.contains("subscribe to opencode")
        }
        return false
    }

    /// Whether another attempt is worth making automatically.
    var isRetryable: Bool {
        if isQuotaExhausted { return false }
        switch self {
        case .http(let status, _, _):
            return status == 429 || status == 408 || (500..<600).contains(status)
        case .transport:
            return true
        default:
            return false
        }
    }

    /// True when the failure suggests we are talking to the wrong endpoint family
    /// for this model, so trying another family is worth it.
    var suggestsRoutingProblem: Bool {
        switch self {
        case .http(let status, let body, _):
            if status == 404 || status == 405 { return true }
            let lowered = body.lowercased()
            return status == 400 && (
                lowered.contains("model") ||
                lowered.contains("not found") ||
                lowered.contains("does not exist") ||
                lowered.contains("unsupported")
            )
        default:
            return false
        }
    }

    /// True when the failure is about an optional parameter we can safely drop.
    var suggestsUnsupportedParameter: Bool {
        if case .http(let status, let body, _) = self, status == 400 {
            let lowered = body.lowercased()
            return lowered.contains("reasoning") ||
                lowered.contains("thinking") ||
                lowered.contains("stream_options") ||
                lowered.contains("unknown field") ||
                lowered.contains("unrecognized")
        }
        return false
    }

    /// True when the gateway refused because this model is not enabled for the account.
    ///
    /// The gateway turns models off per account, and some are blocked by region or by
    /// the account's privacy and data-sharing settings, so the wording varies. Free
    /// endpoints are the clearest example: OpenCode rejects them with a message about
    /// the workspace's Privacy settings. A 404 is *not* included here: that is how a
    /// wrong endpoint family answers, and it is worth trying another one.
    var suggestsModelUnavailable: Bool {
        guard case .http(let status, let body, _) = self else { return false }
        guard status == 400 || status == 403 else { return false }
        let lowered = body.lowercased()
        if lowered.contains("privacy") ||
            lowered.contains("train on request data") ||
            lowered.contains("free endpoints") ||
            lowered.contains("data sharing") {
            return true
        }
        if lowered.contains("model") {
            return lowered.contains("not found") ||
                lowered.contains("not available") ||
                lowered.contains("not enabled") ||
                lowered.contains("disabled") ||
                lowered.contains("does not exist") ||
                lowered.contains("unavailable")
        }
        return lowered.contains("not available") ||
            lowered.contains("not enabled") ||
            lowered.contains("disabled") ||
            lowered.contains("blocked") ||
            lowered.contains("not permitted") ||
            lowered.contains("not allowed") ||
            lowered.contains("denied") ||
            lowered.contains("restricted") ||
            lowered.contains("region") ||
            lowered.contains("unavailable")
    }
}
