import SwiftUI

/// Cost-free usage summary: local tokens and timing.
struct ChatStatsView: View {
    let conversation: Conversation

    @Environment(\.dismiss) private var dismiss

    private var answers: [Message] {
        conversation.sortedMessages.filter { $0.role == .assistant && $0.hasUsage }
    }

    private var totalInput: Int {
        answers.reduce(0) { $0 + $1.totalInputTokens }
    }

    private var totalOutput: Int {
        answers.reduce(0) { $0 + $1.outputTokens }
    }

    private var totalDurationMS: Int {
        answers.reduce(0) { $0 + $1.durationMS }
    }

    private var averageDurationMS: Int {
        guard !answers.isEmpty else { return 0 }
        return totalDurationMS / answers.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Messages", value: "\(answers.count)")
                    LabeledContent("Input tokens", value: totalInput.formatted())
                    LabeledContent("Output tokens", value: totalOutput.formatted())
                    LabeledContent("Total time", value: formatDuration(totalDurationMS))
                    LabeledContent("Average reply", value: formatDuration(averageDurationMS))
                } header: {
                    Text("This chat")
                } footer: {
                    Text("Models run entirely on this device, so there is no per-token charge.")
                }

                if !answers.isEmpty {
                    Section("Replies") {
                        ForEach(answers) { message in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let summary = message.usageSummary {
                                    Text(summary)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Chat timing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func formatDuration(_ milliseconds: Int) -> String {
        guard milliseconds > 0 else { return "—" }
        if milliseconds < 1000 { return "\(milliseconds) ms" }
        return String(format: "%.1f s", Double(milliseconds) / 1000)
    }
}
