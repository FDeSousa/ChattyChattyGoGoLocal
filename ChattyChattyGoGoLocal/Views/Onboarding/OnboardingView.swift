import SwiftUI

/// First-run flow: welcome, then pick a model to download.
struct OnboardingView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedModel: String = LocalModelCatalog.presetModels[1].id
    @State private var downloading = false
    @State private var downloadProgress: Double = 0
    @State private var downloadError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 46))
                                .foregroundStyle(Color.accentColor)
                            Text("ChattyChatty GoGo")
                                .font(.largeTitle.bold())
                            Text("A private chat client that runs its models on this device. No servers, no account, no tracking.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            bullet(
                                icon: "iphone",
                                title: "On-device history",
                                detail: "Every conversation is stored locally and can be searched at any time."
                            )
                            bullet(
                                icon: "internaldrive",
                                title: "Download once, run forever offline",
                                detail: "Pick a model sized for your device. It downloads from Hugging Face and then runs locally."
                            )
                            bullet(
                                icon: "lock.shield",
                                title: "Face ID lock",
                                detail: "Lock the app so nobody else can read your chats."
                            )
                            bullet(
                                icon: "cpu",
                                title: "Local models, tuned for 8 GiB machines",
                                detail: "The presets start tiny and fast — you can always download a larger model later."
                            )
                        }

                        if downloading {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Downloading…")
                                    .font(.headline)
                                ProgressView(value: downloadProgress) {
                                    Text("Download progress")
                                }
                                .progressViewStyle(.linear)
                            }
                        } else {
                            Picker("Starting model", selection: $selectedModel) {
                                ForEach(LocalModelCatalog.presetModels) { model in
                                    VStack(alignment: .leading) {
                                        Text(model.displayName).tag(model.id)
                                        Text("\(model.parameters) · \(model.formattedSize) · \(model.compatibleDevice)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .pickerStyle(.inline)

                            if let downloadError {
                                Label(downloadError, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }

                            Button {
                                Task { await start() }
                            } label: {
                                Text("Download and start")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(selectedModel.isEmpty)
                        }
                    }
                    .padding(24)
                }
            }
        }
    }

    private func bullet(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .frame(width: 28)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func start() async {
        guard let model = LocalModelCatalog.presetModels.first(where: { $0.id == selectedModel }) else { return }
        downloading = true
        downloadProgress = 0
        downloadError = nil
        do {
            _ = try await LocalModelService.shared.load(model: model) { fraction in
                Task { @MainActor in downloadProgress = fraction }
            }
            appState.refreshLocalModels()
            appState.completeOnboarding(modelID: model.id)
        } catch {
            downloadError = error.localizedDescription
        }
        downloading = false
    }
}
