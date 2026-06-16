import SwiftUI

@main
struct ClaudeRemoteApp: App {
    var body: some Scene {
        WindowGroup {
            AppLockGate {
                ContentView()
            }
        }
    }
}
