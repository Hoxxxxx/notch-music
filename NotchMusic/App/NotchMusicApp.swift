import SwiftUI

@main
struct NotchMusicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.musicMonitor)
                .environmentObject(appDelegate.systemActivityMonitor)
                .environmentObject(appDelegate.audioSpectrumMonitor)
                .environmentObject(appDelegate.systemHUDController)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置…") {
                    appDelegate.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
