import SwiftUI

/// The local-model library: presets sized for constrained Apple Silicon, plus
/// a custom Hugging Face repository importer.
@MainActor
struct LocalModelsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var customRepositoryID = ""
    @State private var customError: String?
    @State private var downloadingID: String?
    @State private var downloadProgress: Double = 0

    var body: some View {
        List {
            Section {
                Text("Models run entirely on this device. Downloads come from Hugging Face and are stored in the app's files. Pick presets that fit your memory budget — start with the smallest.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Device-friendly presets") {
                ForEach(appState.localModels) { model in
                    LocalModelRow(
                        model: model,
                        isDefault: appState.defaultModelID == model.id,
                        isDownloading: downloadingID == model.id,
                        progress: downloadProgress,
                        onDownload: { download(model) },
                        onDelete: { delete(model) },
                        onSelect: {
                            appState.setDefaultModel(model.id)
                        }
                    )
                }
            }

            Section("Import a Hugging Face model") {
                TextField("Repository ID, e.g. mlx-community/Llama-3.2-3B-Instruct-4bit", text: $customRepositoryID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if let error = customError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button {
                    importCustom()
                } label: {
                    Label("Download model", systemImage: "arrow.down.circle")
                }
                .disabled(customRepositoryID.trimmingCharacters(in: .whitespaces).isEmpty || downloadingID != nil)
                Text("Only MLX-format repositories with safetensors weights can run. The repository ID is accepted — the app derives the rest from the model card.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Section("Storage") {
                let total = appState.localModels.filter { $0.isDownloaded }.reduce(Int64(0)) { $0 + $1.downloadSizeBytes }
                LabeledContent("Models on this device", value: ByteCountFormatter.string(fromByteCount: total, countStyle: .file))
                Text("Deleting a model frees its storage. Chats and their transcripts stay on device either way.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .navigationTitle("Local Models")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { appState.refreshLocalModels() }
    }

    private func download(_ model: LocalModelInfo) {
        downloadingID = model.id
        downloadProgress = 0
        customError = nil
        Task {
            do {
                _ = try await LocalModelService.shared.load(model: model) { fraction in
                    Task { @MainActor in downloadProgress = fraction }
                }
                appState.refreshLocalModels()
                appState.setDefaultModel(model.id)
            } catch {
                customError = error.localizedDescription
            }
            downloadingID = nil
            downloadProgress = 0
        }
    }

    private func delete(_ model: LocalModelInfo) {
        guard let directory = model.downloadedDirectory else { return }
        try? FileManager.default.removeItem(at: directory)
        LocalModelService.shared.unloadAll()
        appState.refreshLocalModels()
    }

    private func importCustom() {
        let repositoryID = customRepositoryID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repositoryID.isEmpty else { return }
        customError = nil
        guard repositoryID.contains("/") else {
            customError = "Repository IDs look like `mlx-community/Qwen3-4B-4bit`."
            return
        }
        let safe = repositoryID.replacingOccurrences(of: "/", with: "__")
        let model = LocalModelInfo(
            id: safe,
            displayName: repositoryID.components(separatedBy: "/").last ?? repositoryID,
            repositoryID: repositoryID,
            downloadSizeBytes: 0,
            runtimeMemoryEstimate: 0,
            summary: "Custom Hugging Face model.",
            bestFor: ["Custom evaluation"],
            parameters: "Unknown",
            downloadedDirectory: LocalModelCatalog.localModelsDirectory.appendingPathComponent(safe, isDirectory: true)
        )
        downloadingID = model.id
        Task {
            do {
                _ = try await LocalModelService.shared.load(model: model) { fraction in
                    Task { @MainActor in downloadProgress = fraction }
                }
                appState.refreshLocalModels()
                appState.setDefaultModel(model.id)
            } catch {
                customError = error.localizedDescription
            }
            downloadingID = nil
            downloadProgress = 0
        }
    }
}

private struct LocalModelRow: View {
    let model: LocalModelInfo
    let isDefault: Bool
    let isDownloading: Bool
    let progress: Double
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(model.displayName)
                    .font(.headline)
                if isDefault {
                    Text("DEFAULT")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
                Text(model.parameters)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            Text(model.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Label(model.formattedSize, systemImage: "externaldrive")
                Label(model.formattedMemory + " memory", systemImage: "memorychip")
                Text(model.compatibleDevice)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            if isDownloading {
                ProgressView(value: progress) {
                    Text("Downloading…")
                }
                .progressViewStyle(.linear)
            } else if model.isDownloaded {
                HStack(spacing: 10) {
                    Button("Use this model") { onSelect() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Delete", role: .destructive) { onDelete() }
                        .buttonStyle(.plain)
                        .controlSize(.small)
                }
            } else {
                Button("Download") { onDownload() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview("Local models", traits: .fixedLayout(width: 440, height: 956)) {
    NavigationStack {
        LocalModelsView()
            .environment(AppState())
    }
}
