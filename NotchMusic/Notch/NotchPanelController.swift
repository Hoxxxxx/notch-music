import AppKit
import Combine
import SwiftUI

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class NotchPanelController {
    private let musicMonitor: MusicMonitor
    private let systemActivityMonitor: SystemActivityMonitor
    private let audioSpectrumMonitor: AudioSpectrumMonitor
    private let systemHUDController: SystemHUDController
    private let deviceConnectionMonitor: DeviceConnectionMonitor
    private let onOpenSettings: () -> Void
    private let panelState = NotchPanelState()
    private let panel: NotchPanel
    private let lockScreenIsland = LockScreenIslandController()
    private var metrics: NotchMetrics?
    private var isScreenLocked: Bool
    private var screenUnlockTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(
        musicMonitor: MusicMonitor,
        systemActivityMonitor: SystemActivityMonitor,
        audioSpectrumMonitor: AudioSpectrumMonitor,
        systemHUDController: SystemHUDController,
        deviceConnectionMonitor: DeviceConnectionMonitor,
        onOpenSettings: @escaping () -> Void
    ) {
        self.musicMonitor = musicMonitor
        self.systemActivityMonitor = systemActivityMonitor
        self.audioSpectrumMonitor = audioSpectrumMonitor
        self.systemHUDController = systemHUDController
        self.deviceConnectionMonitor = deviceConnectionMonitor
        self.onOpenSettings = onOpenSettings
        self.isScreenLocked = systemActivityMonitor.isScreenLocked

        let panel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.panel = panel

        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true

        let rootView = NotchView(
            musicMonitor: musicMonitor,
            panelState: panelState,
            systemActivityMonitor: systemActivityMonitor,
            audioSpectrumMonitor: audioSpectrumMonitor,
            systemHUDController: systemHUDController,
            deviceConnectionMonitor: deviceConnectionMonitor,
            onOpenSettings: onOpenSettings
        )
        panel.contentView = NSHostingView(rootView: rootView)
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor

        systemActivityMonitor.$isScreenLocked
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isLocked in
                Task { @MainActor in
                    self?.screenLockStateDidChange(isLocked)
                }
            }
            .store(in: &cancellables)
    }

    func show() {
        refreshScreen()
    }

    func screenParametersDidChange() {
        guard !isScreenLocked else { return }
        refreshScreen()
    }

    func expandTemporarily(for seconds: TimeInterval = 6) {
        panelState.expandTemporarily(for: seconds)
    }

    private func refreshScreen() {
        guard let screen = NotchGeometry.activeScreen(),
              let metrics = NotchGeometry.metrics(for: screen) else {
            self.metrics = nil
            panel.orderOut(nil)
            return
        }

        self.metrics = metrics
        panelState.updateMetrics(
            notchWidth: metrics.notchWidth,
            topInset: metrics.topInset,
            notchLeading: metrics.notchLeading,
            notchTrailing: metrics.notchTrailing,
            screenCenterX: metrics.screenCenterX
        )
        updateWindowFrame(metrics: metrics)
        panel.orderFrontRegardless()
        if isScreenLocked {
            _ = lockScreenIsland.enter(panel: panel)
        }
    }

    private func screenLockStateDidChange(_ isLocked: Bool) {
        guard self.isScreenLocked != isLocked else { return }

        self.isScreenLocked = isLocked
        screenUnlockTask?.cancel()
        screenUnlockTask = nil

        guard !isLocked else {
            panelState.collapseForScreenLock()
            _ = lockScreenIsland.enter(panel: panel)
            return
        }

        screenUnlockTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.lockScreenIsland.leave(panel: self.panel)
            self.panelState.restoreAfterScreenLock()
        }
    }

    private func updateWindowFrame(metrics: NotchMetrics) {
        // The panel stays fixed so the SwiftUI spring is the only size animation.
        let size = NotchLayout.windowSize(notchWidth: metrics.notchWidth)
        let frame = NSRect(
            x: metrics.screen.frame.midX - size.width / 2,
            y: metrics.screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        panel.setFrame(frame, display: true)
    }
}
