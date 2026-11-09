import SwiftUI

/// Chat-scoped model picker for downloaded local models.
struct LocalModelPickerView: View {
    @Binding var selection: String
    var title: String = "Model"

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    private var models: [LocalModelInfo] {
        appState.localModels.filter { $0.isDownloaded }
    }

    var body: some View {
        NavigationStack {
            List {
                if models.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("No downloaded models", systemImage: "internaldrive")
                        } description: {
                            Text("Download a model from Local Models first. It runs entirely on this device.")
                        }
                    }
                } else {
                    Section("On this device") {
                        ForEach(models) { model in
                            Button {
                                selection = model.id
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.displayName)
                                            .font(.headline)
                                        Text(model.summary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                        Text("\(model.parameters) · \(model.formattedSize) · runs locally")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                    if selection == model.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
