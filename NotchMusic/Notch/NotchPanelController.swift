import AppKit
import SwiftUI

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class NotchPanelController {
    private let musicMonitor: MusicMonitor
    private let panelState = NotchPanelState()
    private let panel: NotchPanel
    private var metrics: NotchMetrics?

    init(musicMonitor: MusicMonitor) {
        self.musicMonitor = musicMonitor

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
            panelState: panelState
        )
        panel.contentView = NSHostingView(rootView: rootView)
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    }

    func show() {
        refreshScreen()
    }

    func screenParametersDidChange() {
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
            topInset: metrics.topInset
        )
        updateWindowFrame(metrics: metrics)
        panel.orderFrontRegardless()
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
