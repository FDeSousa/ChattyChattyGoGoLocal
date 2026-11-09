import Foundation
import SwiftData
import SwiftUI

/// Sample content used by the Xcode previews.
///
/// Everything lives in an in-memory store, so opening a preview never touches
/// the conversations of the real app.
@MainActor
enum PreviewData {
    static let proMaxSize = CGSize(width: 440, height: 956)

    static func container() -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: Persistence.schema,
            configurations: configuration
        )
        let context = container.mainContext
        for conversation in conversations() {
            context.insert(conversation)
        }
        try? context.save()
        return container
    }

    static func conversations() -> [Conversation] {
        let lisbon = Conversation(title: "Trip to Lisbon", modelID: "qwen3-4b-mlx-4bit")
        lisbon.updatedAt = Date.now.addingTimeInterval(-600)
        lisbon.messages = [
            message(.user, "I have four days in Lisbon in October. What should I plan?"),
            message(
                .assistant,
                """
                October is a great time to visit — the crowds thin out after the first week and the light is lovely.

                ### A loose plan

                - **Day 1** — Alfama and the cathedral, starting early while it is quiet.
                - **Day 2** — Belém and the pasteis de nata.
                - **Day 3** — A day trip to Sintra; leave by 8:30 to beat the buses.
                - **Day 4** — LX Factory and a slow evening in Bairro Alto.

                For the weather, this is usually a good rule of thumb:

                ```swift
                let octoberAverage = (high: 23, low: 16) // °C
                ```

                Want me to turn this into a booked itinerary with times and prices?
                """
            )
        ]

        let concurrency = Conversation(title: "Swift concurrency help", modelID: "qwen3-4b-mlx-4bit")
        concurrency.updatedAt = Date.now.addingTimeInterval(-3600 * 5)
        concurrency.messages = [
            message(.user, "Why does my @MainActor function warn about capturing self in a Task?"),
            message(
                .assistant,
                "Because the closure would otherwise run on a background executor while `self` is main-actor isolated. `Task { @MainActor in … }` keeps the hop explicit, and `MainActor.assumeIsolated` is the escape hatch when you already know you are on the main actor.",
                reasoning: "The warning is about actor isolation, not memory safety."
            )
        ]

        let empty = Conversation(title: "", modelID: "")
        empty.updatedAt = .now

        let older = Conversation(title: "Gift ideas for Dad", modelID: "qwen2.5-3b-instruct-mlx-4bit")
        older.updatedAt = Date.now.addingTimeInterval(-3600 * 24 * 6)
        older.messages = [
            message(.user, "Something under 50 euros for a 70 year old who likes gardening and bad puns."),
            message(.assistant, "A set of heirloom tomato seeds and a tasteful bee-motif tea towel. Add a card with one truly awful pun.")
        ]

        return [lisbon, concurrency, empty, older]
    }

    static func message(
        _ role: MessageRole,
        _ content: String,
        reasoning: String = "",
        failed: Bool = false,
        errorDetail: String = ""
    ) -> Message {
        let message = Message(
            role: role,
            content: content,
            isFailed: failed,
            errorDetail: errorDetail,
            reasoning: reasoning
        )
        message.refreshSearchText()
        return message
    }

    /// A conversation with a single exchange, for the chat preview.
    static func chatPreviewConversation() -> Conversation {
        conversations()[0]
    }
}

/// Wraps preview content in an in-memory store that survives re-renders.
@MainActor
struct PreviewScene<Content: View>: View {
    private let container: ModelContainer
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.container = PreviewData.container()
        self.content = content()
    }

    var body: some View {
        content
            .modelContainer(container)
    }
}
