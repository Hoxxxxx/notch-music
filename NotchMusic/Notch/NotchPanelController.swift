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
    private var pointerTrackingTask: Task<Void, Never>?
    private var isPointerInsideInteractiveRegion = false
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
        panel.contentView?.autoresizingMask = [.width, .height]
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
        startPointerTracking()
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
            panel.ignoresMouseEvents = true
            isPointerInsideInteractiveRegion = false
            _ = lockScreenIsland.enter(panel: panel)
        } else {
            isPointerInsideInteractiveRegion = false
            updatePointerPassthrough()
        }
    }

    private func screenLockStateDidChange(_ isLocked: Bool) {
        guard self.isScreenLocked != isLocked else { return }

        self.isScreenLocked = isLocked
        screenUnlockTask?.cancel()
        screenUnlockTask = nil

        guard !isLocked else {
            panel.ignoresMouseEvents = true
            isPointerInsideInteractiveRegion = false
            panelState.collapseForScreenLock()
            _ = lockScreenIsland.enter(panel: panel)
            return
        }

        screenUnlockTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.lockScreenIsland.leave(panel: self.panel)
            self.isPointerInsideInteractiveRegion = false
            self.panelState.restoreAfterScreenLock()
            self.updatePointerPassthrough()
        }
    }

    private func startPointerTracking() {
        guard pointerTrackingTask == nil else { return }

        pointerTrackingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.updatePointerPassthrough()
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
        }
    }

    private func updatePointerPassthrough() {
        guard !isScreenLocked else { return }

        if NSEvent.pressedMouseButtons != 0, !panel.ignoresMouseEvents {
            return
        }

        let size = panelState.visibleSize
        guard size.width > 0, size.height > 0 else {
            panel.ignoresMouseEvents = true
            return
        }

        let frame = panel.frame
        let interactiveFrame = NSRect(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        let isInside = interactiveFrame.contains(NSEvent.mouseLocation)

        if isInside != isPointerInsideInteractiveRegion {
            isPointerInsideInteractiveRegion = isInside
            panelState.setHovering(isInside)
        }
        panel.ignoresMouseEvents = !isInside
    }

    private func updateWindowFrame(metrics: NotchMetrics) {
        let contentSize = CGSize(
            width: NotchLayout.expandedWidth(
                notchWidth: metrics.notchWidth
            ),
            height: NotchLayout.expandedHeight
        )
        let size = NotchLayout.windowSize(for: contentSize)
        let frame = NSRect(
            x: metrics.screen.frame.midX - size.width / 2,
            y: metrics.screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        panel.setFrame(frame, display: true)
        panel.contentView?.frame = NSRect(origin: .zero, size: frame.size)
        panel.contentView?.layoutSubtreeIfNeeded()
        updatePointerPassthrough()
    }
}
