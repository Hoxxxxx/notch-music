import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let musicMonitor = MusicMonitor()

    private var statusItem: NSStatusItem?
    private var panelController: NotchPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        panelController = NotchPanelController(musicMonitor: musicMonitor)
        panelController?.show()
        configureStatusItem()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        let hasShownWelcome = UserDefaults.standard.bool(forKey: "NotchMusic.hasShownWelcome")
        if !hasShownWelcome {
            UserDefaults.standard.set(true, forKey: "NotchMusic.hasShownWelcome")
            panelController?.expandTemporarily()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        musicMonitor.stop()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "NotchMusic")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "NotchMusic"
        }

        let menu = NSMenu()
        let settingsItem = menu.addItem(
            withTitle: "设置…",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self

        let connectItem = menu.addItem(
            withTitle: "连接 Apple Music",
            action: #selector(connectMusic),
            keyEquivalent: ""
        )
        connectItem.target = self

        let openMusicItem = menu.addItem(
            withTitle: "打开 Apple Music",
            action: #selector(openMusic),
            keyEquivalent: ""
        )
        openMusicItem.target = self

        menu.addItem(.separator())

        let quitItem = menu.addItem(
            withTitle: "退出 NotchMusic",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self

        item.menu = menu
        statusItem = item
    }

    @objc private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func connectMusic() {
        musicMonitor.connect()
        panelController?.expandTemporarily(for: 3)
    }

    @objc private func openMusic() {
        musicMonitor.openAppleMusic()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func screenParametersDidChange() {
        panelController?.screenParametersDidChange()
    }
}
