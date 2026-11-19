import AppKit
import SwiftUI

struct PlaybackButton: View {
    let systemName: String
    let label: String
    let tint: Color
    var activeTint: Color?
    var emphasized = false
    var isActive = false
    var fontSize: CGFloat?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(
                    .system(
                        size: fontSize ?? (emphasized ? 12 : 11),
                        weight: .bold
                    )
                )
                .foregroundStyle(
                    isActive
                        ? activeTint ?? tint
                        : isHovering
                            ? tint
                        : Color.white.opacity(emphasized ? 1 : 0.76)
                )
                .frame(width: 28, height: 28)
                .contentShape(Circle())
                .animation(
                    .easeOut(duration: 0.14),
                    value: isHovering
                )
                .animation(
                    .easeOut(duration: 0.16),
                    value: isActive
                )
                .onHover { hovering in
                    isHovering = hovering
                }
        }
        .buttonStyle(PlaybackPressStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct PlaybackPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(
                .easeOut(duration: 0.08),
                value: configuration.isPressed
            )
    }
}

struct NotchActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Color.white.opacity(configuration.isPressed ? 0.22 : 0.13),
                in: Capsule()
            )
    }
}

private struct HoverParallaxModifier: ViewModifier {
    let size: CGFloat
    var isEnabled = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation = CGSize.zero
    @State private var isHovering = false

    private let maxTilt: CGFloat = 6

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(Double(rotation.height)),
                axis: (x: 1, y: 0, z: 0),
                perspective: 0.55
            )
            .rotation3DEffect(
                .degrees(Double(rotation.width)),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.55
            )
            .scaleEffect(isHovering && !reduceMotion ? 1.015 : 1)
            .animation(
                .spring(response: 0.26, dampingFraction: 0.82),
                value: rotation
            )
            .animation(
                .spring(response: 0.28, dampingFraction: 0.86),
                value: isHovering
            )
            .onContinuousHover { phase in
                guard isEnabled, !reduceMotion else {
                    reset()
                    return
                }

                switch phase {
                case .active(let location):
                    isHovering = true
                    updateRotation(at: location)
                case .ended:
                    reset()
                }
            }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled {
                    reset()
                }
            }
            .onChange(of: reduceMotion) { _, reduced in
                if reduced {
                    reset()
                }
            }
    }

    private func updateRotation(at location: CGPoint) {
        let x = min(max(location.x / size, 0), 1) - 0.5
        let y = min(max(location.y / size, 0), 1) - 0.5
        rotation = CGSize(
            width: x * maxTilt * 2,
            height: -y * maxTilt * 2
        )
    }

    private func reset() {
        rotation = .zero
        isHovering = false
    }
}

extension View {
    func hoverParallax(size: CGFloat, isEnabled: Bool = true) -> some View {
        modifier(HoverParallaxModifier(size: size, isEnabled: isEnabled))
    }
}

struct TrackpadPageSwipeView: NSViewRepresentable {
    let excludedLeadingWidth: CGFloat
    let onSwipe: (ContentPageTransitionDirection) -> Void

    func makeNSView(context: Context) -> TrackpadPageSwipeNSView {
        let view = TrackpadPageSwipeNSView()
        view.excludedLeadingWidth = excludedLeadingWidth
        view.onSwipe = onSwipe
        return view
    }

    func updateNSView(_ nsView: TrackpadPageSwipeNSView, context: Context) {
        nsView.excludedLeadingWidth = excludedLeadingWidth
        nsView.onSwipe = onSwipe
    }
}

final class TrackpadPageSwipeNSView: NSView {
    var excludedLeadingWidth: CGFloat = 0
    var onSwipe: ((ContentPageTransitionDirection) -> Void)?

    private var eventMonitor: Any?
    private var accumulatedDeltaX: CGFloat = 0
    private var hasTriggered = false
    private let triggerThreshold: CGFloat = 55

    override var acceptsFirstResponder: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installEventMonitor()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            removeEventMonitor()
        }
    }

    private func installEventMonitor() {
        guard eventMonitor == nil, window != nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.scrollWheel]
        ) { [weak self] event in
            self?.handleScrollWheel(event) ?? event
        }
    }

    private func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        resetGesture()
    }

    private func handleScrollWheel(_ event: NSEvent) -> NSEvent? {
        guard isTrackpadPageSwipe(event) else {
            resetGesture()
            return event
        }

        if event.phase.contains(.began) {
            accumulatedDeltaX = 0
            hasTriggered = false
        }

        accumulatedDeltaX += event.scrollingDeltaX

        if !hasTriggered,
           abs(accumulatedDeltaX) >= triggerThreshold {
            hasTriggered = true
            let direction: ContentPageTransitionDirection =
                accumulatedDeltaX < 0 ? .forward : .backward
            onSwipe?(direction)
        }

        if event.phase.contains(.ended)
            || event.phase.contains(.cancelled) {
            resetGesture()
        }

        return nil
    }

    private func isTrackpadPageSwipe(_ event: NSEvent) -> Bool {
        guard event.phase != [],
              abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY),
              let window else {
            return false
        }

        let inWindow = window.convertPoint(
            fromScreen: NSEvent.mouseLocation
        )
        let location = convert(inWindow, from: nil)
        let isInside =
            location.x >= 0
            && location.x <= bounds.width
            && location.y >= 0
            && location.y <= bounds.height
        let isInsideDateWheel =
            excludedLeadingWidth > 0
            && location.x <= excludedLeadingWidth

        return isInside && !isInsideDateWheel
    }

    private func resetGesture() {
        accumulatedDeltaX = 0
        hasTriggered = false
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }
}
