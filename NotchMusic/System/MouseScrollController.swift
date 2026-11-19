import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import QuartzCore

enum MouseScrollSettings {
    static let activeKey = "NotchMusic.mouseScroll.active"
    static let enabledKey = "NotchMusic.mouseScroll.enabled"
    static let reverseVerticalKey = "NotchMusic.mouseScroll.reverseVertical"
    static let reverseHorizontalKey = "NotchMusic.mouseScroll.reverseHorizontal"
    static let speedKey = "NotchMusic.mouseScroll.speed"
    static let durationKey = "NotchMusic.mouseScroll.duration"
    static let speedRange = 1.0...10.0
    static let durationRange = 1.0...5.0
    static let step = 33.6

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            activeKey: true,
            enabledKey: true,
            reverseVerticalKey: false,
            reverseHorizontalKey: false,
            speedKey: 2.90,
            durationKey: 4.50
        ])
    }
}

@MainActor
final class MouseScrollController: NSObject, ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var accessibilityGranted = false

    private struct Configuration {
        let active: Bool
        let smoothing: Bool
        let reverseVertical: Bool
        let reverseHorizontal: Bool
        let speed: Double
        let duration: Double

        var needsEventTap: Bool {
            active && (smoothing || reverseVertical || reverseHorizontal)
        }
    }

    private struct ScrollDelta {
        var x: Double = 0
        var y: Double = 0

        var isZero: Bool {
            x == 0 && y == 0
        }
    }

    private static let syntheticMarker: Int64 = 0x4E4F5443_48534352

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var displayLink: CADisplayLink?
    private var pending = ScrollDelta()
    private var template: CGEvent?
    private var targetPID: pid_t = 0
    private var defaultsObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?

    override init() {
        MouseScrollSettings.registerDefaults()
        super.init()

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applyConfiguration()
            }
        }

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAvailability()
            }
        }
    }

    func start() {
        refreshAvailability()
    }

    func stop() {
        stopEventTap()
        stopDisplayLink()
        resetSmoothing()
    }

    func refreshAvailability() {
        accessibilityGranted = AXIsProcessTrusted()
        applyConfiguration()
    }

    func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            self?.refreshAvailability()
        }
    }

    func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func applyConfiguration() {
        let configuration = currentConfiguration()

        if accessibilityGranted, configuration.needsEventTap {
            startEventTapIfNeeded()
        } else {
            stopEventTap()
            stopDisplayLink()
            resetSmoothing()
        }
    }

    private func currentConfiguration() -> Configuration {
        let defaults = UserDefaults.standard
        return Configuration(
            active: defaults.bool(
                forKey: MouseScrollSettings.activeKey
            ),
            smoothing: defaults.bool(
                forKey: MouseScrollSettings.enabledKey
            ),
            reverseVertical: defaults.bool(
                forKey: MouseScrollSettings.reverseVerticalKey
            ),
            reverseHorizontal: defaults.bool(
                forKey: MouseScrollSettings.reverseHorizontalKey
            ),
            speed: max(
                MouseScrollSettings.speedRange.lowerBound,
                min(
                    MouseScrollSettings.speedRange.upperBound,
                    defaults.double(forKey: MouseScrollSettings.speedKey)
                )
            ),
            duration: min(
                MouseScrollSettings.durationRange.upperBound,
                max(
                    MouseScrollSettings.durationRange.lowerBound,
                    defaults.double(forKey: MouseScrollSettings.durationKey)
                )
            )
        )
    }

    private func startEventTapIfNeeded() {
        guard eventTap == nil else {
            isActive = true
            return
        }

        let eventMask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            isActive = false
            return
        }

        let source = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            tap,
            0
        )
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isActive = true
    }

    private func stopEventTap() {
        if let runLoopSource {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                runLoopSource,
                .commonModes
            )
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
        isActive = false
    }

    private static let eventTapCallback: CGEventTapCallBack = {
        _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let controller = Unmanaged<MouseScrollController>
            .fromOpaque(userInfo)
            .takeUnretainedValue()
        return MainActor.assumeIsolated {
            controller.handle(type: type, event: event)
        }
    }

    private func handle(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            resetSmoothing()
            return Unmanaged.passUnretained(event)
        }

        guard type == .scrollWheel else {
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.eventSourceUserData)
                != Self.syntheticMarker else {
            return Unmanaged.passUnretained(event)
        }
        guard !Self.isTrackpadEvent(event) else {
            resetSmoothing()
            return Unmanaged.passUnretained(event)
        }

        let rawDelta = Self.normalizedDelta(
            Self.rawScrollDelta(for: event)
        )
        guard !rawDelta.isZero else {
            return Unmanaged.passUnretained(event)
        }

        let configuration = currentConfiguration()
        Self.applyReversal(
            to: event,
            vertical: configuration.reverseVertical,
            horizontal: configuration.reverseHorizontal
        )

        guard configuration.smoothing else {
            return Unmanaged.passUnretained(event)
        }

        let pid = pid_t(
            event.getIntegerValueField(.eventTargetUnixProcessID)
        )
        guard pid > 0 else {
            return Unmanaged.passUnretained(event)
        }

        if pid != targetPID {
            resetSmoothing()
            targetPID = pid
        }
        template = event.copy()

        let scaled = ScrollDelta(
            x: rawDelta.x * (configuration.reverseHorizontal ? -1 : 1)
                * configuration.speed,
            y: rawDelta.y * (configuration.reverseVertical ? -1 : 1)
                * configuration.speed
        )
        pending.x += scaled.x
        pending.y += scaled.y
        startDisplayLinkIfNeeded()
        return nil
    }

    private static func rawScrollDelta(for event: CGEvent) -> ScrollDelta {
        ScrollDelta(
            x: axisDelta(
                from: event,
                point: .scrollWheelEventPointDeltaAxis2,
                fixed: .scrollWheelEventFixedPtDeltaAxis2,
                line: .scrollWheelEventDeltaAxis2
            ),
            y: axisDelta(
                from: event,
                point: .scrollWheelEventPointDeltaAxis1,
                fixed: .scrollWheelEventFixedPtDeltaAxis1,
                line: .scrollWheelEventDeltaAxis1
            )
        )
    }

    private static func normalizedDelta(_ delta: ScrollDelta) -> ScrollDelta {
        ScrollDelta(
            x: normalizedAxis(delta.x),
            y: normalizedAxis(delta.y)
        )
    }

    private static func normalizedAxis(_ value: Double) -> Double {
        guard value != 0, abs(value) < MouseScrollSettings.step else {
            return value
        }
        return value < 0 ? -MouseScrollSettings.step : MouseScrollSettings.step
    }

    private static func durationTransition(for duration: Double) -> Double {
        let upperLimit = 5.0 + 0.2
        let value = 1 - (duration / upperLimit).squareRoot()
        return (1000 * value).rounded() / 1000
    }

    private static func axisDelta(
        from event: CGEvent,
        point: CGEventField,
        fixed: CGEventField,
        line: CGEventField
    ) -> Double {
        let pointValue = event.getDoubleValueField(point)
        if abs(pointValue) > 0.0001 {
            return pointValue
        }

        let fixedValue = event.getDoubleValueField(fixed)
        if abs(fixedValue) > 0.0001 {
            return fixedValue
        }

        return Double(event.getIntegerValueField(line)) * 10
    }

    private static func applyReversal(
        to event: CGEvent,
        vertical: Bool,
        horizontal: Bool
    ) {
        if vertical {
            event.setIntegerValueField(
                .scrollWheelEventDeltaAxis1,
                value: -event.getIntegerValueField(
                    .scrollWheelEventDeltaAxis1
                )
            )
            event.setDoubleValueField(
                .scrollWheelEventPointDeltaAxis1,
                value: -event.getDoubleValueField(
                    .scrollWheelEventPointDeltaAxis1
                )
            )
            event.setDoubleValueField(
                .scrollWheelEventFixedPtDeltaAxis1,
                value: -event.getDoubleValueField(
                    .scrollWheelEventFixedPtDeltaAxis1
                )
            )
        }

        if horizontal {
            event.setIntegerValueField(
                .scrollWheelEventDeltaAxis2,
                value: -event.getIntegerValueField(
                    .scrollWheelEventDeltaAxis2
                )
            )
            event.setDoubleValueField(
                .scrollWheelEventPointDeltaAxis2,
                value: -event.getDoubleValueField(
                    .scrollWheelEventPointDeltaAxis2
                )
            )
            event.setDoubleValueField(
                .scrollWheelEventFixedPtDeltaAxis2,
                value: -event.getDoubleValueField(
                    .scrollWheelEventFixedPtDeltaAxis2
                )
            )
        }
    }

    private static func isTrackpadEvent(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.scrollWheelEventScrollPhase) != 0
            || event.getIntegerValueField(
                .scrollWheelEventMomentumPhase
            ) != 0
            || event.getIntegerValueField(
                .scrollWheelEventScrollCount
            ) != 0
    }

    private func startDisplayLinkIfNeeded() {
        if let displayLink {
            displayLink.isPaused = false
            return
        }

        let screen = NSScreen.screens.first {
            $0.frame.contains(NSEvent.mouseLocation)
        } ?? NSScreen.main
        guard let screen else {
            return
        }

        let link = screen.displayLink(
            target: self,
            selector: #selector(displayLinkDidFire(_:))
        )
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func displayLinkDidFire(_ link: CADisplayLink) {
        guard targetPID > 0, template != nil else {
            stopDisplayLink()
            resetSmoothing()
            return
        }

        let configuration = currentConfiguration()
        guard configuration.smoothing else {
            stopDisplayLink()
            resetSmoothing()
            return
        }

        let blend = Self.durationTransition(for: configuration.duration)
        var step = ScrollDelta(
            x: pending.x * blend,
            y: pending.y * blend
        )
        pending.x -= step.x
        pending.y -= step.y

        if abs(pending.x) < 0.05 {
            step.x += pending.x
            pending.x = 0
        }
        if abs(pending.y) < 0.05 {
            step.y += pending.y
            pending.y = 0
        }

        guard !step.isZero else {
            stopDisplayLink()
            resetSmoothing()
            return
        }

        post(step)
        if pending.isZero {
            stopDisplayLink()
            resetSmoothing()
        }
    }

    private func post(_ delta: ScrollDelta) {
        guard let template,
              let event = template.copy(),
              targetPID > 0 else {
            return
        }

        event.setDoubleValueField(
            .scrollWheelEventPointDeltaAxis1,
            value: delta.y
        )
        event.setDoubleValueField(
            .scrollWheelEventPointDeltaAxis2,
            value: delta.x
        )
        event.setDoubleValueField(
            .scrollWheelEventIsContinuous,
            value: 1.0
        )
        event.setIntegerValueField(
            .eventSourceUserData,
            value: Self.syntheticMarker
        )
        event.postToPid(targetPID)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func resetSmoothing() {
        pending = ScrollDelta()
        template = nil
        targetPID = 0
    }
}
