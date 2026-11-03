import AudioToolbox
import CoreAudio
import CoreGraphics
import Darwin
import Foundation
import ObjectiveC.runtime

struct SystemControlResult {
    let level: Double
    let isMuted: Bool
}

final class SystemControlBackend {
    private let audio = SystemAudioControl()
    private let displayBrightness = DisplayBrightnessControl()
    private let keyboardBrightness = KeyboardBrightnessControl()

    var availability: SystemHUDAvailability {
        SystemHUDAvailability(
            volume: audio.isAvailable,
            displayBrightness: displayBrightness.isAvailable,
            keyboardBrightness: keyboardBrightness.isAvailable
        )
    }

    func perform(
        _ control: SystemHUDControl,
        action: MediaKeyAction,
        step: Double
    ) -> SystemControlResult? {
        let delta = Float(step)

        switch control {
        case .volume:
            return audio.perform(action: action, step: delta)
        case .displayBrightness:
            return displayBrightness.perform(action: action, step: delta)
        case .keyboardBrightness:
            return keyboardBrightness.perform(action: action, step: delta)
        }
    }

    func currentState(
        _ control: SystemHUDControl
    ) -> SystemControlResult? {
        switch control {
        case .volume:
            return audio.currentState
        case .displayBrightness:
            return displayBrightness.currentState
        case .keyboardBrightness:
            return keyboardBrightness.currentState
        }
    }

    func playVolumeFeedback() {
        AudioServicesPlaySystemSound(1104)
    }
}

private final class SystemAudioControl {
    private enum VolumeControl {
        case single(
            selector: AudioObjectPropertySelector,
            element: AudioObjectPropertyElement
        )
        case channels([AudioObjectPropertyElement])
    }

    private var emulatedMuteVolume: [AudioDeviceID: Float] = [:]

    var isAvailable: Bool {
        guard let device = defaultOutputDevice() else { return false }
        return volumeControl(for: device) != nil
    }

    var currentState: SystemControlResult? {
        guard let device = defaultOutputDevice(),
              let control = volumeControl(for: device),
              let volume = readVolume(device: device, control: control) else {
            return nil
        }

        let isMuted = muteAddress(device: device).flatMap {
            readMute(device: device, address: $0)
        } ?? (emulatedMuteVolume[device] != nil)

        return SystemControlResult(
            level: isMuted ? 0 : Double(volume),
            isMuted: isMuted
        )
    }

    func perform(
        action: MediaKeyAction,
        step: Float
    ) -> SystemControlResult? {
        guard let device = defaultOutputDevice(),
              let control = volumeControl(for: device),
              var volume = readVolume(device: device, control: control) else {
            return nil
        }

        let nativeMute = muteAddress(device: device)
        let isMuted = nativeMute.flatMap {
            readMute(device: device, address: $0)
        } ?? (emulatedMuteVolume[device] != nil)

        switch action {
        case .mute:
            if let nativeMute {
                guard writeUInt32(
                    isMuted ? 0 : 1,
                    device: device,
                    address: nativeMute
                ) else {
                    return nil
                }
                let newMuted = readMute(
                    device: device,
                    address: nativeMute
                ) ?? !isMuted
                return SystemControlResult(
                    level: newMuted ? 0 : Double(volume),
                    isMuted: newMuted
                )
            }

            if let remembered = emulatedMuteVolume.removeValue(forKey: device) {
                volume = remembered
            } else {
                emulatedMuteVolume[device] = volume
                volume = 0
            }
            guard writeVolume(volume, device: device, control: control) else {
                return nil
            }
            return SystemControlResult(
                level: Double(volume),
                isMuted: emulatedMuteVolume[device] != nil
            )

        case .increase, .decrease:
            if let nativeMute, isMuted {
                guard writeUInt32(0, device: device, address: nativeMute) else {
                    return nil
                }
            }
            if let remembered = emulatedMuteVolume.removeValue(forKey: device) {
                volume = remembered
                guard writeVolume(volume, device: device, control: control) else {
                    return nil
                }
            }

            volume += action == .increase ? step : -step
            volume = min(max(volume, 0), 1)
            guard writeVolume(volume, device: device, control: control) else {
                return nil
            }

            let confirmed = readVolume(
                device: device,
                control: control
            ) ?? volume
            return SystemControlResult(
                level: Double(confirmed),
                isMuted: false
            )
        }
    }

    private func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        guard status == noErr, device != kAudioObjectUnknown else {
            return nil
        }
        return device
    }

    private func volumeControl(for device: AudioDeviceID) -> VolumeControl? {
        let virtualSelector =
            kAudioHardwareServiceDeviceProperty_VirtualMainVolume
        if isSettable(
            device: device,
            selector: virtualSelector,
            element: kAudioObjectPropertyElementMain
        ) {
            return .single(
                selector: virtualSelector,
                element: kAudioObjectPropertyElementMain
            )
        }

        if isSettable(
            device: device,
            selector: kAudioDevicePropertyVolumeScalar,
            element: kAudioObjectPropertyElementMain
        ) {
            return .single(
                selector: kAudioDevicePropertyVolumeScalar,
                element: kAudioObjectPropertyElementMain
            )
        }

        let channels = (1...8).compactMap {
            channel -> AudioObjectPropertyElement? in
            let element = AudioObjectPropertyElement(channel)
            return isSettable(
                device: device,
                selector: kAudioDevicePropertyVolumeScalar,
                element: element
            ) ? element : nil
        }
        return channels.isEmpty ? nil : .channels(Array(channels.prefix(2)))
    }

    private func isSettable(
        device: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        element: AudioObjectPropertyElement
    ) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(
            device,
            &address,
            &settable
        ) == noErr && settable.boolValue
    }

    private func readVolume(
        device: AudioDeviceID,
        control: VolumeControl
    ) -> Float? {
        switch control {
        case .single(let selector, let element):
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            return readFloat32(device: device, address: &address)
        case .channels(let elements):
            let values = elements.compactMap { element -> Float? in
                var address = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyVolumeScalar,
                    mScope: kAudioDevicePropertyScopeOutput,
                    mElement: element
                )
                return readFloat32(device: device, address: &address)
            }
            guard !values.isEmpty else { return nil }
            return values.reduce(0, +) / Float(values.count)
        }
    }

    private func writeVolume(
        _ value: Float,
        device: AudioDeviceID,
        control: VolumeControl
    ) -> Bool {
        let value = min(max(value, 0), 1)
        switch control {
        case .single(let selector, let element):
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            return writeFloat32(value, device: device, address: &address)
        case .channels(let elements):
            return elements.reduce(true) { success, element in
                var address = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyVolumeScalar,
                    mScope: kAudioDevicePropertyScopeOutput,
                    mElement: element
                )
                return writeFloat32(
                    value,
                    device: device,
                    address: &address
                ) && success
            }
        }
    }

    private func muteAddress(
        device: AudioDeviceID
    ) -> AudioObjectPropertyAddress? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(
            device,
            &address,
            &settable
        ) == noErr, settable.boolValue else {
            return nil
        }
        return address
    }

    private func readMute(
        device: AudioDeviceID,
        address: AudioObjectPropertyAddress
    ) -> Bool? {
        var address = address
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(
            device,
            &address,
            0,
            nil,
            &size,
            &value
        ) == noErr else {
            return nil
        }
        return value != 0
    }

    private func readFloat32(
        device: AudioDeviceID,
        address: inout AudioObjectPropertyAddress
    ) -> Float? {
        var value: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        guard AudioObjectGetPropertyData(
            device,
            &address,
            0,
            nil,
            &size,
            &value
        ) == noErr else {
            return nil
        }
        return min(max(value, 0), 1)
    }

    private func writeFloat32(
        _ value: Float,
        device: AudioDeviceID,
        address: inout AudioObjectPropertyAddress
    ) -> Bool {
        var value = value
        return AudioObjectSetPropertyData(
            device,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float>.size),
            &value
        ) == noErr
    }

    private func writeUInt32(
        _ value: UInt32,
        device: AudioDeviceID,
        address: AudioObjectPropertyAddress
    ) -> Bool {
        var address = address
        var value = value
        return AudioObjectSetPropertyData(
            device,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &value
        ) == noErr
    }
}

private final class DisplayBrightnessControl {
    private typealias GetBrightnessFunction = @convention(c) (
        CGDirectDisplayID,
        UnsafeMutablePointer<Float>
    ) -> Int32
    private typealias SetBrightnessFunction = @convention(c) (
        CGDirectDisplayID,
        Float
    ) -> Int32

    private let displayID: CGDirectDisplayID?
    private let getBrightness: GetBrightnessFunction?
    private let setBrightness: SetBrightnessFunction?

    init() {
        let handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_LAZY
        )
        let getSymbol = handle.flatMap {
            dlsym($0, "DisplayServicesGetBrightness")
        }
        let setSymbol = handle.flatMap {
            dlsym($0, "DisplayServicesSetBrightness")
        }

        getBrightness = getSymbol.map {
            unsafeBitCast($0, to: GetBrightnessFunction.self)
        }
        setBrightness = setSymbol.map {
            unsafeBitCast($0, to: SetBrightnessFunction.self)
        }
        displayID = Self.builtInDisplayID()
    }

    var isAvailable: Bool {
        displayID != nil
            && getBrightness != nil
            && setBrightness != nil
            && currentLevel() != nil
    }

    var currentState: SystemControlResult? {
        guard let level = currentLevel() else { return nil }
        return SystemControlResult(
            level: Double(level),
            isMuted: false
        )
    }

    func perform(
        action: MediaKeyAction,
        step: Float
    ) -> SystemControlResult? {
        guard action != .mute,
              let current = currentLevel() else {
            return nil
        }
        let level = min(
            max(current + (action == .increase ? step : -step), 0),
            1
        )
        guard set(level) else { return nil }
        return SystemControlResult(
            level: Double(currentLevel() ?? level),
            isMuted: false
        )
    }

    private func currentLevel() -> Float? {
        guard let displayID, let getBrightness else { return nil }
        var level: Float = 0
        guard getBrightness(displayID, &level) == 0,
              level.isFinite else {
            return nil
        }
        return min(max(level, 0), 1)
    }

    private func set(_ level: Float) -> Bool {
        guard let displayID, let setBrightness else { return false }
        return setBrightness(displayID, level) == 0
    }

    private static func builtInDisplayID() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success,
              count > 0 else {
            return nil
        }

        var displays = [CGDirectDisplayID](
            repeating: 0,
            count: Int(count)
        )
        guard CGGetOnlineDisplayList(
            count,
            &displays,
            &count
        ) == .success else {
            return nil
        }
        return displays.first { CGDisplayIsBuiltin($0) != 0 }
    }
}

private final class KeyboardBrightnessControl {
    private typealias CopyIdentifiersFunction = @convention(c) (
        AnyObject,
        Selector
    ) -> Unmanaged<AnyObject>?
    private typealias IsBuiltInFunction = @convention(c) (
        AnyObject,
        Selector,
        UInt64
    ) -> UInt8
    private typealias GetBrightnessFunction = @convention(c) (
        AnyObject,
        Selector,
        UInt64
    ) -> Float
    private typealias SetBrightnessFunction = @convention(c) (
        AnyObject,
        Selector,
        Float,
        UInt64
    ) -> UInt8

    private let client: AnyObject?
    private let copyIdentifiersSelector = NSSelectorFromString(
        "copyKeyboardBacklightIDs"
    )
    private let isBuiltInSelector = NSSelectorFromString("isKeyboardBuiltIn:")
    private let getBrightnessSelector = NSSelectorFromString(
        "brightnessForKeyboard:"
    )
    private let setBrightnessSelector = NSSelectorFromString(
        "setBrightness:forKeyboard:"
    )
    private let copyIdentifiers: CopyIdentifiersFunction?
    private let isBuiltIn: IsBuiltInFunction?
    private let getBrightness: GetBrightnessFunction?
    private let setBrightness: SetBrightnessFunction?

    init() {
        let bundle = Bundle(
            path: "/System/Library/PrivateFrameworks/CoreBrightness.framework"
        )
        _ = bundle?.load()

        guard let clientClass = NSClassFromString(
            "KeyboardBrightnessClient"
        ) as? NSObject.Type else {
            client = nil
            copyIdentifiers = nil
            isBuiltIn = nil
            getBrightness = nil
            setBrightness = nil
            return
        }

        client = clientClass.init()
        copyIdentifiers = Self.implementation(
            of: "copyKeyboardBacklightIDs",
            on: clientClass,
            as: CopyIdentifiersFunction.self
        )
        isBuiltIn = Self.implementation(
            of: "isKeyboardBuiltIn:",
            on: clientClass,
            as: IsBuiltInFunction.self
        )
        getBrightness = Self.implementation(
            of: "brightnessForKeyboard:",
            on: clientClass,
            as: GetBrightnessFunction.self
        )
        setBrightness = Self.implementation(
            of: "setBrightness:forKeyboard:",
            on: clientClass,
            as: SetBrightnessFunction.self
        )
    }

    var isAvailable: Bool {
        current() != nil
    }

    var currentState: SystemControlResult? {
        guard let state = current() else { return nil }
        return SystemControlResult(
            level: Double(state.level),
            isMuted: false
        )
    }

    func perform(
        action: MediaKeyAction,
        step: Float
    ) -> SystemControlResult? {
        guard action != .mute, let state = current() else { return nil }
        let level = min(
            max(state.level + (action == .increase ? step : -step), 0),
            1
        )
        guard set(level, keyboardID: state.keyboardID) else {
            return nil
        }
        return SystemControlResult(
            level: Double(current()?.level ?? level),
            isMuted: false
        )
    }

    private func current() -> (keyboardID: UInt64, level: Float)? {
        guard let client,
              let copyIdentifiers,
              let isBuiltIn,
              let getBrightness,
              let identifiers = copyIdentifiers(
                  client,
                  copyIdentifiersSelector
              )?.takeRetainedValue() as? [NSNumber] else {
            return nil
        }

        for value in identifiers {
            let keyboardID = value.uint64Value
            guard isBuiltIn(client, isBuiltInSelector, keyboardID) != 0 else {
                continue
            }
            let level = getBrightness(
                client,
                getBrightnessSelector,
                keyboardID
            )
            guard level.isFinite else { return nil }
            return (keyboardID, min(max(level, 0), 1))
        }
        return nil
    }

    private func set(_ level: Float, keyboardID: UInt64) -> Bool {
        guard let client, let setBrightness else { return false }
        return setBrightness(
            client,
            setBrightnessSelector,
            level,
            keyboardID
        ) != 0
    }

    private static func implementation<Function>(
        of name: String,
        on cls: AnyClass,
        as type: Function.Type
    ) -> Function? {
        let selector = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(cls, selector) else {
            return nil
        }
        let implementation = method_getImplementation(method)
        return unsafeBitCast(implementation, to: Function.self)
    }
}
