import SwiftData
import SwiftUI

/// App settings for the local build.
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]

    @State private var showingInstructions = false
    @State private var showingDeleteAll = false

    var body: some View {
        NavigationStack {
            Form {
                cardSection
                modelSection
                privacySection
                dataSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingInstructions) {
                GlobalInstructionsView()
            }
            .alert("Delete every chat?", isPresented: $showingDeleteAll) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    for conversation in conversations {
                        modelContext.delete(conversation)
                    }
                    try? modelContext.save()
                }
            } message: {
                Text("This removes all conversations and messages from this device. It cannot be undone.")
            }
        }
    }

    // MARK: - Sections

    private var modelSection: some View {
        Section {
            NavigationLink {
                LocalModelsView()
            } label: {
                Label("Local models", systemImage: "internaldrive")
            }
            Toggle(isOn: Binding(
                get: { Preferences.toolsEnabled },
                set: { Preferences.toolsEnabled = $0 }
            )) {
                Label("Allow app tools", systemImage: "wrench.and.screwdriver")
            }
        } header: {
            Text("Local models")
        } footer: {
            Text("Models run entirely on this device. App tools ask before sharing private data or creating calendar items.")
        }
    }

    private var cardSection: some View {
        Section {
            Button {
                showingInstructions = true
            } label: {
                HStack {
                    Label("Global instructions", systemImage: "text.bubble")
                    Spacer()
                    Text(Preferences.systemPrompt.isEmpty ? "None" : "Set")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Picker(selection: Binding(
                get: { appState.theme },
                set: { appState.setTheme($0) }
            )) {
                ForEach(ThemeMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            } label: {
                Label("Appearance", systemImage: "circle.lefthalf.filled")
            }
        } header: {
            Text("Assistant")
        }
    }

    private var privacySection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { appState.biometricEnabled },
                set: { appState.setBiometricEnabled($0) }
            )) {
                Label("Lock with Face ID", systemImage: "faceid")
            }
        } header: {
            Text("Privacy")
        } footer: {
            Text("The app locks itself when you leave it. Nothing leaves this device.")
        }
    }

    private var dataSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteAll = true
            } label: {
                Label("Delete all chats", systemImage: "trash")
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Chats live in SwiftData on this device only.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Device memory", value: "\(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GiB")
            LabeledContent("Models on device", value: appState.localModels.filter { $0.isDownloaded }.count.description)
        } header: {
            Text("About")
        }
    }
}

/// Global system prompt.
struct GlobalInstructionsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("These instructions are sent with every new chat. Individual chats can override them.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 8)

                TextEditor(text: $text)
                    .font(.body)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    .scrollContentBackground(.hidden)
            }
            .navigationTitle("Global instructions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Preferences.systemPrompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                    }
                }
            }
            .onAppear { text = Preferences.systemPrompt }
        }
    }
}

#Preview("Settings", traits: .fixedLayout(width: 440, height: 956)) {
    PreviewScene {
        SettingsView()
            .environment(AppState())
    }
}
