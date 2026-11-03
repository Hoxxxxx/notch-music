import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum MediaKeyAction: Equatable, Sendable {
    case increase
    case decrease
    case mute
}

enum MediaKeyPhase: Equatable, Sendable {
    case down
    case up
}

struct MediaKeyEvent: Equatable, Sendable {
    let control: SystemHUDControl
    let action: MediaKeyAction
    let phase: MediaKeyPhase
    let isFineAdjustment: Bool
}

final class MediaKeyInterceptor: @unchecked Sendable {
    var onKeyDown: ((MediaKeyEvent) -> Void)?

    private static let systemDefinedEventType: UInt32 = 14
    private static let auxiliaryControlSubtype = 8
    private static let keyDownState = 0xA
    private static let keyUpState = 0xB

    private let lock = NSLock()
    private var enabledControls = Set<SystemHUDControl>()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isRunning: Bool {
        guard let eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: eventTap)
    }

    func updateEnabledControls(_ controls: Set<SystemHUDControl>) {
        lock.lock()
        enabledControls = controls
        lock.unlock()
    }

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }
        guard AXIsProcessTrusted() else { return false }

        let eventMask = CGEventMask(1) << Self.systemDefinedEventType
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
    }

    private static let eventTapCallback: CGEventTapCallBack = {
        _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let interceptor = Unmanaged<MediaKeyInterceptor>
            .fromOpaque(userInfo)
            .takeUnretainedValue()
        return interceptor.handle(type: type, event: event)
    }

    private func handle(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type.rawValue == Self.systemDefinedEventType,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == Self.auxiliaryControlSubtype else {
            return Unmanaged.passUnretained(event)
        }

        let data1 = nsEvent.data1
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let keyState = (data1 & 0x0000_FF00) >> 8

        let phase: MediaKeyPhase
        switch keyState {
        case Self.keyDownState:
            phase = .down
        case Self.keyUpState:
            phase = .up
        default:
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let usesKeyboardBrightness = flags.contains(.maskCommand)
        let control: SystemHUDControl
        let action: MediaKeyAction

        switch keyCode {
        case 0:
            control = .volume
            action = .increase
        case 1:
            control = .volume
            action = .decrease
        case 7:
            control = .volume
            action = .mute
        case 2:
            control = usesKeyboardBrightness
                ? .keyboardBrightness
                : .displayBrightness
            action = .increase
        case 3:
            control = usesKeyboardBrightness
                ? .keyboardBrightness
                : .displayBrightness
            action = .decrease
        case 21:
            control = .keyboardBrightness
            action = .increase
        case 22:
            control = .keyboardBrightness
            action = .decrease
        default:
            return Unmanaged.passUnretained(event)
        }

        guard isEnabled(control) else {
            return Unmanaged.passUnretained(event)
        }

        let mediaEvent = MediaKeyEvent(
            control: control,
            action: action,
            phase: phase,
            isFineAdjustment: flags.contains(.maskAlternate)
                && flags.contains(.maskShift)
        )

        if phase == .down {
            onKeyDown?(mediaEvent)
        }

        return nil
    }

    private func isEnabled(_ control: SystemHUDControl) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return enabledControls.contains(control)
    }
}
