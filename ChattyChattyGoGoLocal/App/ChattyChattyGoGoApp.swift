import Foundation
import SwiftUI

/// The app entry point.
@main
struct ChattyChattyGoGoLocalApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .preferredColorScheme(appState.theme.colorScheme)
        }
        .modelContainer(Persistence.makeContainer())
    }
}
