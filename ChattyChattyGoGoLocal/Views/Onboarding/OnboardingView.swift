import SwiftUI

/// First-run flow: welcome, then download a starting model.
struct OnboardingView: View {
    @Environment(AppState.self) private var appState

    @State private var step: Step = .welcome
    @State private var selectedModel: String = "qwen3-1.7b-mlx-4bit"
    @State private var downloading = false
    @State private var downloadProgress: Double = 0
    @State private var downloadError: String?

    private enum Step: Int {
        case welcome
        case model
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch step {
                case .welcome:
                    welcomeStep
                case .model:
                    modelStep
                }
            }
            .animation(.easeInOut(duration: 0.25), value: step)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if step != .welcome {
                        Button("Back") { step = .welcome }
                    }
                }
            }
        }
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(Color.accentColor)
                    Text("ChattyChatty Local")
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
                        detail: "Models come from Hugging Face and then run locally. Choose one sized for your device."
                    )
                    bullet(
                        icon: "lock.shield",
                        title: "Face ID lock",
                        detail: "Lock the app so nobody else can read your chats."
                    )
                    bullet(
                        icon: "cpu",
                        title: "Local models, tuned for 8 GiB machines",
                        detail: "Presets start tiny and fast — you can download a larger model later."
                    )
                    bullet(
                        icon: "wrench.and.screwdriver",
                        title: "App tools, always approved",
                        detail: "Calculator, OCR, saved-chat search, calendar, reminders and contacts — the model asks before using private data."
                    )
                }

                Button {
                    step = .model
                } label: {
                    Text("Choose a model")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
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

    // MARK: - Model

    private var modelStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pick a starting model")
                        .font(.title2.bold())
                    Text("It downloads to this device and runs locally. This iPhone has \(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GiB of memory.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Picker("Model", selection: $selectedModel) {
                    ForEach(LocalModelCatalog.presetModels) { model in
                        VStack(alignment: .leading) {
                            Text("\(model.displayName) · \(model.parameters)")
                            Text("\(model.formattedSize) download · \(model.formattedMemory) memory")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .tag(model.id)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                if let selected = LocalModelCatalog.presetModels.first(where: { $0.id == selectedModel }) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selected.summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(selected.compatibleDevice)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                    if let downloadError {
                        Label(downloadError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }

                    Button {
                        Task { await start() }
                    } label: {
                        Text("Download and start chatting")
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
