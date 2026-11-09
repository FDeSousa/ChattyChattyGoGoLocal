import Foundation
import SwiftUI

/// App-wide state: onboarding, lock state, theme, and the local model library.
@MainActor
@Observable
final class AppState {
    private(set) var isLocked: Bool = false
    private(set) var hasCompletedOnboarding: Bool = false
    private(set) var defaultModelID: String = ""
    private(set) var theme: ThemeMode = .system
    private(set) var biometricEnabled: Bool = false
    /// Local models available for this device — downloaded or ready to download.
    private(set) var localModels: [LocalModelInfo] = []

    let biometrics = BiometricService()

    init() {
        if UITestSupport.isUITesting {
            Preferences.resetAll()
        }
        hasCompletedOnboarding = Preferences.hasCompletedOnboarding
        defaultModelID = Preferences.defaultModelID
        theme = Preferences.theme
        biometricEnabled = Preferences.biometricEnabled
        isLocked = biometricEnabled
        refreshLocalModels()
    }

    func refresh() {
        hasCompletedOnboarding = Preferences.hasCompletedOnboarding
        defaultModelID = Preferences.defaultModelID
        theme = Preferences.theme
        biometricEnabled = Preferences.biometricEnabled
        if !biometricEnabled { isLocked = false }
        refreshLocalModels()
    }

    /// Re-scan the on-disk model library.
    func refreshLocalModels() {
        localModels = LocalModelCatalog.allModels()
        // Prefer downloaded presets as the default when nothing is set.
        if defaultModelID.isEmpty {
            if let firstDownloaded = localModels.first(where: { $0.isDownloaded })?.id {
                defaultModelID = firstDownloaded
                Preferences.defaultModelID = firstDownloaded
            }
        }
    }

    /// The model the chat should use right now.
    var currentModel: LocalModelInfo? {
        if !defaultModelID.isEmpty,
           let chosen = localModels.first(where: { $0.id == defaultModelID }) {
            return chosen
        }
        return localModels.first(where: { $0.isDownloaded }) ?? localModels.first
    }

    /// Called when the onboarding flow finishes.
    func completeOnboarding(modelID: String) {
        Preferences.defaultModelID = modelID
        Preferences.hasCompletedOnboarding = true
        defaultModelID = modelID
        hasCompletedOnboarding = true
    }

    func setDefaultModel(_ id: String) {
        Preferences.defaultModelID = id
        defaultModelID = id
    }

    func setTheme(_ mode: ThemeMode) {
        Preferences.theme = mode
        theme = mode
    }

    func setBiometricEnabled(_ enabled: Bool) {
        Preferences.biometricEnabled = enabled
        biometricEnabled = enabled
        if !enabled { isLocked = false }
    }

    func unlock() async {
        guard biometricEnabled else {
            isLocked = false
            return
        }
        guard case .available = biometrics.availability else {
            isLocked = false
            return
        }
        let ok = await biometrics.authenticate(reason: "Unlock your conversations")
        if ok { isLocked = false }
    }

    func lock() {
        guard biometricEnabled else { return }
        isLocked = true
    }
}
