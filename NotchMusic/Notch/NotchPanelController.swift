import AppKit
import Combine
import QuartzCore
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
    private var cancellables = Set<AnyCancellable>()

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

        panelState.$isExpanded
            .removeDuplicates()
            .sink { [weak self] expanded in
                self?.updateFrame(expanded: expanded, animated: true)
            }
            .store(in: &cancellables)
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
        updateFrame(expanded: panelState.isExpanded, animated: false)
        panel.orderFrontRegardless()
    }

    private func updateFrame(expanded: Bool, animated: Bool) {
        guard let metrics else { return }

        let width: CGFloat = expanded
            ? max(340, metrics.notchWidth + 150)
            : max(230, metrics.notchWidth + 56)
        let height: CGFloat = expanded
            ? 164
            : max(32, metrics.topInset)

        let frame = NSRect(
            x: metrics.screen.frame.midX - width / 2,
            y: metrics.screen.frame.maxY - height,
            width: width,
            height: height
        )

        guard animated, panel.isVisible, panel.frame != frame else {
            panel.setFrame(frame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = expanded ? 0.28 : 0.18
            context.timingFunction = CAMediaTimingFunction(
                name: expanded ? .easeOut : .easeInEaseOut
            )
            panel.animator().setFrame(frame, display: true)
        }
    }
}
