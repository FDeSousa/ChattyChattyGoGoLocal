import Foundation
import SwiftData

/// A single conversation. Everything about it lives on-device.
@Model
final class Conversation {
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    /// Local model id used for this chat. Empty means "use the global default".
    var modelID: String = ""
    /// Per-chat system prompt override. Empty means "use the global default".
    var systemPrompt: String = ""
    /// Stable per-conversation identifier, used to look up the local MLX session.
    var sessionID: String = ""
    /// False once the user has named the chat themselves.
    var titleIsAutomatic = true

    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    var messages: [Message] = []

    init(
        id: UUID = UUID(),
        title: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        modelID: String = "",
        systemPrompt: String = "",
        sessionID: String = ""
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.modelID = modelID
        self.systemPrompt = systemPrompt
        self.sessionID = sessionID
    }

    /// The local session identifier for this chat, created on first use.
    func resolvedSessionID() -> String {
        if sessionID.isEmpty {
            sessionID = UUID().uuidString
        }
        return sessionID
    }

    /// Title used before the first reply lands.
    var displayTitle: String {
        title.isEmpty ? "New Chat" : title
    }

    var lastMessage: Message? {
        messages.sorted { $0.createdAt < $1.createdAt }.last
    }

    var sortedMessages: [Message] {
        messages.sorted { $0.createdAt < $1.createdAt }
    }
}
