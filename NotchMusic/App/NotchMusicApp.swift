import SwiftUI

@main
struct NotchMusicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.musicMonitor)
        }
    }
}
