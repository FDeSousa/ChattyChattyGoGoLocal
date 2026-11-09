import Foundation
import SwiftUI

enum ThemeMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Small, non-secret app settings.
@MainActor
enum Preferences {
    private enum Key {
        static let defaultModelID = "defaultModelID"
        static let systemPrompt = "systemPrompt"
        static let theme = "theme"
        static let biometricEnabled = "biometricEnabled"
        static let completedOnboarding = "completedOnboarding"
        static let temperature = "temperature"
        static let toolsEnabled = "toolsEnabled"
        static let maxTokens = "maxTokens"
    }

    private static let defaults = UserDefaults.standard

    static var defaultModelID: String {
        get { defaults.string(forKey: Key.defaultModelID) ?? "" }
        set { defaults.set(newValue, forKey: Key.defaultModelID) }
    }

    static var systemPrompt: String {
        get { defaults.string(forKey: Key.systemPrompt) ?? "" }
        set { defaults.set(newValue, forKey: Key.systemPrompt) }
    }

    static var temperature: Double? {
        get {
            guard defaults.object(forKey: Key.temperature) != nil else { return nil }
            return defaults.double(forKey: Key.temperature)
        }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.temperature)
            } else {
                defaults.removeObject(forKey: Key.temperature)
            }
        }
    }

    static var maxTokens: Int {
        get { defaults.integer(forKey: Key.maxTokens) > 0 ? defaults.integer(forKey: Key.maxTokens) : 2048 }
        set { defaults.set(newValue, forKey: Key.maxTokens) }
    }

    /// Whether model-invoked app tools are offered on local models.
    /// Enabled by default for new and upgraded installs.
    static var toolsEnabled: Bool {
        get { (defaults.object(forKey: Key.toolsEnabled) as? Bool) ?? true }
        set { defaults.set(newValue, forKey: Key.toolsEnabled) }
    }

    static var theme: ThemeMode {
        get {
            guard let raw = defaults.string(forKey: Key.theme), let mode = ThemeMode(rawValue: raw) else { return .system }
            return mode
        }
        set { defaults.set(newValue, forKey: Key.theme) }
    }

    static var biometricEnabled: Bool {
        get { defaults.bool(forKey: Key.biometricEnabled) }
        set { defaults.set(newValue, forKey: Key.biometricEnabled) }
    }

    static var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.completedOnboarding) }
        set { defaults.set(newValue, forKey: Key.completedOnboarding) }
    }

    /// Wipes every stored preference. Used when the app is launched by a UI test.
    static func resetAll() {
        for key in [
            Key.defaultModelID,
            Key.systemPrompt,
            Key.theme,
            Key.biometricEnabled,
            Key.completedOnboarding,
            Key.temperature,
            Key.toolsEnabled,
            Key.maxTokens
        ] {
            defaults.removeObject(forKey: key)
        }
    }
}
