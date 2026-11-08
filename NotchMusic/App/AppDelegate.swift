import AppKit
import Combine
import CoreText
import SwiftUI

enum MenuBarIconStyle: String, CaseIterable, Identifiable {
    static let storageKey = "NotchMusic.menuBarIconStyle"

    case notch = "notch"
    case note = "music.note"
    case playlist = "music.note.list"
    case notes = "music.quarternote.3"
    case waveform = "waveform"
    case headphones = "headphones"
    case record = "opticaldisc.fill"

    var id: String { rawValue }

    var systemImage: String? {
        switch self {
        case .notch:
            return nil
        default:
            return rawValue
        }
    }

    var displayName: String {
        switch self {
        case .notch:
            return "刘海"
        case .note:
            return "音符"
        case .playlist:
            return "播放列表"
        case .notes:
            return "多重音符"
        case .waveform:
            return "波形"
        case .headphones:
            return "耳机"
        case .record:
            return "唱片"
        }
    }
}

enum MenuBarIconRenderer {
    static let notchIcon: NSImage = makeNotchIcon()

    static func image(for style: MenuBarIconStyle) -> NSImage? {
        if style == .notch {
            return notchIcon
        }

        guard let systemImage = style.systemImage else { return nil }
        let image = NSImage(
            systemSymbolName: systemImage,
            accessibilityDescription: "NotchMusic"
        )
        image?.isTemplate = true
        return image
    }

    private static func makeNotchIcon() -> NSImage {
        let pointSize: CGFloat = 18
        let image = NSImage(
            size: NSSize(width: pointSize, height: pointSize),
            flipped: true
        ) { rect in
            let side = min(rect.width, rect.height)
            let origin = CGPoint(
                x: rect.midX - side / 2,
                y: rect.midY - side / 2
            )

            func roundedPath(
                _ frame: CGRect,
                radius: CGFloat
            ) -> NSBezierPath {
                NSBezierPath(
                    roundedRect: NSRect(
                        x: origin.x + frame.minX * side,
                        y: origin.y + frame.minY * side,
                        width: frame.width * side,
                        height: frame.height * side
                    ),
                    xRadius: radius * side,
                    yRadius: radius * side
                )
            }

            let ring = roundedPath(
                CGRect(x: 0.055, y: 0.055, width: 0.89, height: 0.89),
                radius: 0.245
            )
            ring.append(
                roundedPath(
                    CGRect(x: 0.138, y: 0.138, width: 0.724, height: 0.724),
                    radius: 0.16
                )
            )
            ring.windingRule = .evenOdd
            NSColor.white.setFill()
            ring.fill()

            let fillFrame = CGRect(
                x: 0.178,
                y: 0.178,
                width: 0.644,
                height: 0.644
            )
            let fillPath = roundedPath(fillFrame, radius: 0.12)
            if let context = NSGraphicsContext.current?.cgContext,
               let gradient = CGGradient(
                   colorsSpace: CGColorSpaceCreateDeviceRGB(),
                   colors: [
                       NSColor.white.withAlphaComponent(0).cgColor,
                       NSColor.white.withAlphaComponent(0.8).cgColor
                   ] as CFArray,
                   locations: [0, 1]
               ) {
                context.saveGState()
                context.addPath(fillPath.cgPath)
                context.clip()
                let centerX = origin.x + fillFrame.midX * side
                context.drawLinearGradient(
                    gradient,
                    start: CGPoint(
                        x: centerX,
                        y: origin.y + fillFrame.minY * side
                    ),
                    end: CGPoint(
                        x: centerX,
                        y: origin.y + fillFrame.maxY * side
                    ),
                    options: []
                )
                context.restoreGState()
            }

            let notch = roundedPath(
                CGRect(x: 0.383, y: 0.178, width: 0.234, height: 0.115),
                radius: 0.0575
            )
            notch.append(
                NSBezierPath(
                    rect: NSRect(
                        x: origin.x + 0.383 * side,
                        y: origin.y + 0.178 * side,
                        width: 0.234 * side,
                        height: 0.0575 * side
                    )
                )
            )
            NSColor.white.setFill()
            notch.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}

enum ApplicationIconStyle: String, CaseIterable, Identifiable {
    static let storageKey = "NotchMusic.applicationIconStyle"

    case violet = "violet"
    case ocean = "ocean"
    case sunset = "sunset"
    case mint = "mint"
    case rose = "rose"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .violet:
            return "紫罗兰"
        case .ocean:
            return "海洋蓝"
        case .sunset:
            return "日落橙"
        case .mint:
            return "薄荷绿"
        case .rose:
            return "玫瑰粉"
        }
    }

    var assetName: String {
        switch self {
        case .violet:
            return "AppIconDefault"
        case .ocean:
            return "AppIconOcean"
        case .sunset:
            return "AppIconSunset"
        case .mint:
            return "AppIconMint"
        case .rose:
            return "AppIconRose"
        }
    }

    static func migrateStoredValueIfNeeded() {
        let defaults = UserDefaults.standard
        guard let storedValue = defaults.string(forKey: storageKey) else {
            return
        }
        guard ApplicationIconStyle(rawValue: storedValue) == nil else {
            return
        }
        defaults.set(
            ApplicationIconStyle.ocean.rawValue,
            forKey: storageKey
        )
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let musicMonitor = MusicMonitor()
    let systemActivityMonitor = SystemActivityMonitor()
    let audioSpectrumMonitor = AudioSpectrumMonitor()
    let systemHUDController = SystemHUDController()
    let deviceConnectionMonitor = DeviceConnectionMonitor()

    private var statusItem: NSStatusItem?
    private var panelController: NotchPanelController?
    private var settingsWindowController: NSWindowController?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerBundledFonts()
        MusicControlLayoutSettings.migrateStoredValueIfNeeded()
        SoundHUDSettings.migrateColoredVolumePreferenceIfNeeded()
        ApplicationIconStyle.migrateStoredValueIfNeeded()
        SystemHUDStyle.migrateRemovedStylesIfNeeded()
        NSApp.setActivationPolicy(.accessory)
        applyApplicationIcon()

        panelController = NotchPanelController(
            musicMonitor: musicMonitor,
            systemActivityMonitor: systemActivityMonitor,
            audioSpectrumMonitor: audioSpectrumMonitor,
            systemHUDController: systemHUDController,
            deviceConnectionMonitor: deviceConnectionMonitor,
            onOpenSettings: showSettings
        )
        panelController?.show()
        configureStatusItem()
        observeMenuBarIconChanges()
        observeApplicationIconChanges()
        observePlaybackForSpectrum()
        observeScreenLockForHUD()
        systemHUDController.start()
        deviceConnectionMonitor.start()

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

    private func registerBundledFonts() {
        guard let fontURL = Bundle.main.url(
            forResource: "fusion-pixel-12px-proportional-zh_hans",
            withExtension: "ttf"
        ) else {
            return
        }

        CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        musicMonitor.stop()
        systemActivityMonitor.stop()
        audioSpectrumMonitor.stop()
        systemHUDController.stop()
        deviceConnectionMonitor.stop()
        cancellables.removeAll()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        systemHUDController.refreshAvailability()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.toolTip = "NotchMusic"

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
        updateStatusItemImage()
    }

    private func observeMenuBarIconChanges() {
        NotificationCenter.default.publisher(
            for: UserDefaults.didChangeNotification
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusItemImage()
            }
        }
        .store(in: &cancellables)
    }

    private func observeApplicationIconChanges() {
        NotificationCenter.default.publisher(
            for: UserDefaults.didChangeNotification
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            Task { @MainActor in
                self?.applyApplicationIcon()
            }
        }
        .store(in: &cancellables)
    }

    private func applyApplicationIcon() {
        let storedValue = UserDefaults.standard.string(
            forKey: ApplicationIconStyle.storageKey
        )
        let style = storedValue.flatMap(ApplicationIconStyle.init(rawValue:))
            ?? .ocean

        guard let image = NSImage(named: style.assetName) else { return }
        NSApp.applicationIconImage = image
    }

    private func updateStatusItemImage() {
        guard let button = statusItem?.button else { return }

        let storedValue = UserDefaults.standard.string(
            forKey: MenuBarIconStyle.storageKey
        )
        let style = storedValue.flatMap(MenuBarIconStyle.init(rawValue:))
            ?? .notch
        button.image = MenuBarIconRenderer.image(for: style)
    }

    private func observePlaybackForSpectrum() {
        musicMonitor.$snapshot
            .map { $0?.isPlaying == true }
            .removeDuplicates()
            .sink { [weak self] isPlaying in
                self?.audioSpectrumMonitor.setPlaybackActive(isPlaying)
            }
            .store(in: &cancellables)
    }

    private func observeScreenLockForHUD() {
        systemHUDController.setScreenLocked(
            systemActivityMonitor.isScreenLocked
        )
        systemActivityMonitor.$isScreenLocked
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isLocked in
                self?.systemHUDController.setScreenLocked(isLocked)
            }
            .store(in: &cancellables)
    }

    @objc func showSettings() {
        NSApp.activate(ignoringOtherApps: true)

        // The status-item menu is still tracking when its action fires.
        // Defer opening until the menu closes and the app finishes activating.
        DispatchQueue.main.async {
            self.showSettingsWindow()
        }
    }

    private func showSettingsWindow() {
        if settingsWindowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 720),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "NotchMusic 设置"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.contentViewController = NSHostingController(
                rootView: SettingsView()
                    .environmentObject(musicMonitor)
                    .environmentObject(systemActivityMonitor)
                    .environmentObject(audioSpectrumMonitor)
                    .environmentObject(systemHUDController)
            )
            window.contentView?.wantsLayer = true
            window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
            window.center()
            settingsWindowController = NSWindowController(window: window)
        }

        if let window = settingsWindowController?.window,
           let screen = NSScreen.main,
           !screen.visibleFrame.intersects(window.frame) {
            window.center()
        }

        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window == settingsWindowController?.window else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.settingsWindowController = nil
        }
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
