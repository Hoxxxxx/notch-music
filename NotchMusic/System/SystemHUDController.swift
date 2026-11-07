import AppKit
import ApplicationServices
import Combine
import CoreAudio
import Foundation

enum SystemHUDStyle: String, CaseIterable, Identifiable {
    case island
    case customOSD

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .island:
            return "灵动岛"
        case .customOSD:
            return "自定义 OSD"
        }
    }

    static let storageKey = "NotchMusic.systemHUDStyle"

    static func migrateRemovedStylesIfNeeded(
        defaults: UserDefaults = .standard
    ) {
        switch defaults.string(forKey: storageKey) {
        case "vertical", "circular":
            defaults.set(
                SystemHUDStyle.customOSD.rawValue,
                forKey: storageKey
            )
        default:
            break
        }
    }
}

enum SystemHUDControl: String, CaseIterable, Identifiable, Sendable {
    case volume
    case displayBrightness
    case keyboardBrightness

    var id: String { rawValue }

    var title: String {
        switch self {
        case .volume:
            return "音量"
        case .displayBrightness:
            return "屏幕亮度"
        case .keyboardBrightness:
            return "键盘背光"
        }
    }

    func symbolName(level: Double, isMuted: Bool) -> String {
        switch self {
        case .volume:
            if isMuted || level <= 0.001 {
                return "speaker.slash.fill"
            }
            if level < 0.34 {
                return "speaker.1.fill"
            }
            if level < 0.67 {
                return "speaker.2.fill"
            }
            return "speaker.3.fill"
        case .displayBrightness:
            return level < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .keyboardBrightness:
            return "keyboard.fill"
        }
    }
}

struct SystemHUDPresentation: Equatable, Sendable {
    let control: SystemHUDControl
    let level: Double
    let isMuted: Bool
    let isFineAdjustment: Bool
}

struct SystemHUDAvailability: Equatable {
    let volume: Bool
    let displayBrightness: Bool
    let keyboardBrightness: Bool

    func supports(_ control: SystemHUDControl) -> Bool {
        switch control {
        case .volume:
            return volume
        case .displayBrightness:
            return displayBrightness
        case .keyboardBrightness:
            return keyboardBrightness
        }
    }
}

enum SystemHUDSettings {
    static let style = SystemHUDStyle.storageKey
    static let volumeEnabled = "NotchMusic.systemHUD.volumeEnabled"
    static let brightnessEnabled = "NotchMusic.systemHUD.brightnessEnabled"
    static let keyboardBrightnessEnabled =
        "NotchMusic.systemHUD.keyboardBrightnessEnabled"
    static let audioFeedbackEnabled =
        "NotchMusic.systemHUD.audioFeedbackEnabled"
    static let hapticFeedbackEnabled =
        "NotchMusic.systemHUD.hapticFeedbackEnabled"
    static let coloredVolumeEnabled =
        "NotchMusic.systemHUD.coloredVolumeEnabled"
    static let nativeControlsVisible =
        "NotchMusic.systemHUD.showsNativeControls"
    static let volumeStep = "NotchMusic.systemHUD.volumeStep"
    static let volumeFineStep = "NotchMusic.systemHUD.volumeFineStep"
    static let brightnessStep = "NotchMusic.systemHUD.brightnessStep"
    static let brightnessFineStep =
        "NotchMusic.systemHUD.brightnessFineStep"

    static func isControlEnabled(
        _ control: SystemHUDControl,
        defaults: UserDefaults = .standard
    ) -> Bool {
        bool(
            for: storageKey(for: control),
            defaultValue: true,
            defaults: defaults
        )
    }

    static func isAudioFeedbackEnabled(
        defaults: UserDefaults = .standard
    ) -> Bool {
        bool(
            for: audioFeedbackEnabled,
            defaultValue: false,
            defaults: defaults
        )
    }

    static func isHapticFeedbackEnabled(
        defaults: UserDefaults = .standard
    ) -> Bool {
        bool(
            for: hapticFeedbackEnabled,
            defaultValue: false,
            defaults: defaults
        )
    }

    static func showsNativeControls(
        defaults: UserDefaults = .standard
    ) -> Bool {
        bool(
            for: nativeControlsVisible,
            defaultValue: false,
            defaults: defaults
        )
    }

    static func step(
        for control: SystemHUDControl,
        fine: Bool,
        defaults: UserDefaults = .standard
    ) -> Double {
        let key: String
        let fallback: Double

        switch control {
        case .volume:
            key = fine ? volumeFineStep : volumeStep
            fallback = fine ? 2 : 5
        case .displayBrightness, .keyboardBrightness:
            key = fine ? brightnessFineStep : brightnessStep
            fallback = fine ? 2 : 5
        }

        let value = defaults.object(forKey: key) == nil
            ? fallback
            : Double(defaults.integer(forKey: key))
        return min(max(value, 1), 20) / 100
    }

    private static func storageKey(for control: SystemHUDControl) -> String {
        switch control {
        case .volume:
            return volumeEnabled
        case .displayBrightness:
            return brightnessEnabled
        case .keyboardBrightness:
            return keyboardBrightnessEnabled
        }
    }

    private static func bool(
        for key: String,
        defaultValue: Bool,
        defaults: UserDefaults
    ) -> Bool {
        guard defaults.object(forKey: key) != nil else {
            return defaultValue
        }
        return defaults.bool(forKey: key)
    }
}

enum SoundHUDStyle: String, CaseIterable, Identifiable {
    case white
    case accent
    case decibel

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .white:
            return "白色"
        case .accent:
            return "跟随封面"
        case .decibel:
            return "分贝"
        }
    }
}

enum SoundHUDSpeed: String, CaseIterable, Identifiable {
    case smooth
    case fast
    case instant

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .smooth:
            return "平滑"
        case .fast:
            return "快速"
        case .instant:
            return "即时"
        }
    }

    var systemImage: String {
        switch self {
        case .smooth:
            return "waveform.path"
        case .fast:
            return "water.waves"
        case .instant:
            return "bolt.fill"
        }
    }
}

enum SoundHUDContent: String, CaseIterable, Identifiable {
    case symbol
    case device

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .symbol:
            return "符号"
        case .device:
            return "设备"
        }
    }
}

enum SoundHUDSettings {
    static let duration = "NotchMusic.soundHUD.duration"
    static let style = "NotchMusic.soundHUD.style"
    static let showsPercentage = "NotchMusic.soundHUD.showsPercentage"
    static let hidesLabel = "NotchMusic.soundHUD.hidesLabel"
    static let speed = "NotchMusic.soundHUD.speed"
    static let content = "NotchMusic.soundHUD.content"

    static let defaultDuration: TimeInterval = 1.5

    static func duration(defaults: UserDefaults = .standard) -> TimeInterval {
        guard defaults.object(forKey: duration) != nil else {
            return defaultDuration
        }
        return min(max(defaults.double(forKey: duration), 0.5), 5)
    }

    static func migrateColoredVolumePreferenceIfNeeded(
        defaults: UserDefaults = .standard
    ) {
        let migrationKey = "NotchMusic.soundHUD.migratedColoredVolume"
        guard !defaults.bool(forKey: migrationKey) else { return }
        defaults.set(true, forKey: migrationKey)
        guard defaults.object(forKey: style) == nil,
              defaults.object(forKey: SystemHUDSettings.coloredVolumeEnabled)
                != nil else {
            return
        }

        let usesColor = defaults.bool(
            forKey: SystemHUDSettings.coloredVolumeEnabled
        )
        defaults.set(
            (usesColor ? SoundHUDStyle.accent : .white).rawValue,
            forKey: style
        )
    }
}

enum LightingHUDStyle: String, CaseIterable, Identifiable {
    case white
    case accent
    case glow

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .white:
            return "白色"
        case .accent:
            return "强调色"
        case .glow:
            return "光晕"
        }
    }
}

enum LightingHUDSettings {
    static let duration = "NotchMusic.lightingHUD.duration"
    static let style = "NotchMusic.lightingHUD.style"
    static let speed = "NotchMusic.lightingHUD.speed"
    static let showsPercentage = "NotchMusic.lightingHUD.showsPercentage"
    static let hidesLabel = "NotchMusic.lightingHUD.hidesLabel"

    static let defaultDuration: TimeInterval = 1.5

    static func duration(defaults: UserDefaults = .standard) -> TimeInterval {
        guard defaults.object(forKey: duration) != nil else {
            return defaultDuration
        }
        return min(max(defaults.double(forKey: duration), 0.5), 5)
    }
}

struct SoundOutputDevice {
    enum Kind {
        case airPods
        case airPodsMax
        case headphones
        case builtIn
        case display
        case other
    }

    let name: String
    let kind: Kind
    let manufacturer: String?
    let transport: UInt32?

    var symbolName: String {
        switch kind {
        case .airPods:
            return "airpodspro"
        case .airPodsMax:
            return "airpodsmax"
        case .headphones:
            return "headphones"
        case .builtIn:
            return "hifispeaker.fill"
        case .display:
            return "display"
        case .other:
            return "speaker.wave.2.fill"
        }
    }

    var isLikelyAirPods: Bool {
        if kind == .airPods || kind == .airPodsMax {
            return true
        }
        return transport == kAudioDeviceTransportTypeBluetooth
            && manufacturer?.localizedCaseInsensitiveContains("Apple")
                == true
    }

    var airPodsModel: AirPodsModelKind? {
        guard isLikelyAirPods else { return nil }
        if kind == .airPodsMax {
            return .airPodsMax
        }
        if name.localizedCaseInsensitiveContains("Max") {
            return .airPodsMax
        }
        if name.localizedCaseInsensitiveContains("Pro") {
            return .airPodsPro
        }
        return kind == .airPods ? .airPods : .airPodsPro
    }

    static func preferredAirPodsModel() -> AirPodsModelKind? {
        current()?.airPodsModel
    }

    static func current() -> SoundOutputDevice? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        ) == noErr, deviceID != kAudioObjectUnknown else {
            return nil
        }

        let name = stringProperty(
            deviceID: deviceID,
            selector: kAudioObjectPropertyName
        ) ?? "扬声器"
        let manufacturer = stringProperty(
            deviceID: deviceID,
            selector: kAudioObjectPropertyManufacturer
        )
        let transport = uint32Property(
            deviceID: deviceID,
            selector: kAudioDevicePropertyTransportType
        )
        return SoundOutputDevice(
            name: name,
            kind: kind(name: name, transport: transport),
            manufacturer: manufacturer,
            transport: transport
        )
    }

    private static func kind(
        name: String,
        transport: UInt32?
    ) -> Kind {
        let lowercased = name.lowercased()
        if lowercased.contains("airpods max") {
            return .airPodsMax
        }
        if lowercased.contains("airpods") {
            return .airPods
        }
        if lowercased.contains("headphone")
            || lowercased.contains("耳机") {
            return .headphones
        }
        guard let transport else { return .other }

        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:
            return .builtIn
        case kAudioDeviceTransportTypeBluetooth:
            return .headphones
        case kAudioDeviceTransportTypeHDMI,
             kAudioDeviceTransportTypeDisplayPort:
            return .display
        default:
            return .other
        }
    }

    private static func stringProperty(
        deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &value
        ) == noErr, let value else {
            return nil
        }
        return value.takeRetainedValue() as String
    }

    private static func uint32Property(
        deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &value
        ) == noErr else {
            return nil
        }
        return value
    }
}

@MainActor
final class SystemHUDController: ObservableObject {
    @Published private(set) var presentation: SystemHUDPresentation?
    @Published private(set) var availability = SystemHUDAvailability(
        volume: false,
        displayBrightness: false,
        keyboardBrightness: false
    )
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var interceptionActive = false
    @Published private(set) var passiveMonitoringActive = false

    private let backend = SystemControlBackend()
    private let interceptor = MediaKeyInterceptor()
    private var defaultsObserver: NSObjectProtocol?
    private var hideTask: Task<Void, Never>?
    private var passiveMonitorTask: Task<Void, Never>?
    private var passiveResumeTask: Task<Void, Never>?
    private var passiveControls = Set<SystemHUDControl>()
    private var lastPassiveStates: [SystemHUDControl: PassiveState] = [:]
    private var lastVolumeOutputDeviceID: AudioDeviceID?
    private var ignorePassiveVolumeUntil: TimeInterval = 0
    private var isScreenLocked = false
    private var ignoresPassiveChanges = false

    private struct PassiveState: Equatable {
        let level: Double
        let isMuted: Bool
    }

    init() {
        interceptor.onKeyDown = { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
        observePreferenceChanges()
    }

    func start() {
        refreshAvailability()
        applyConfiguration()
    }

    func stop() {
        hideTask?.cancel()
        hideTask = nil
        passiveResumeTask?.cancel()
        passiveResumeTask = nil
        interceptor.stop()
        stopPassiveMonitoring()
        interceptionActive = false
        presentation = nil

        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
            self.defaultsObserver = nil
        }
    }

    func setScreenLocked(_ locked: Bool) {
        guard isScreenLocked != locked else { return }
        isScreenLocked = locked
        passiveResumeTask?.cancel()
        passiveResumeTask = nil

        if locked {
            ignoresPassiveChanges = false
            hideTask?.cancel()
            hideTask = nil
            presentation = nil
        } else {
            ignoresPassiveChanges = true
            refreshPassiveBaselines()
            passiveResumeTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard !Task.isCancelled, let self else { return }
                self.ignoresPassiveChanges = false
                self.refreshPassiveBaselines()
            }
        }
    }

    func refreshAvailability() {
        accessibilityGranted = AXIsProcessTrusted()
        let newAvailability = backend.availability
        if availability != newAvailability {
            availability = newAvailability
        }
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
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func observePreferenceChanges() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applyConfiguration()
            }
        }
    }

    private func applyConfiguration() {
        let defaults = UserDefaults.standard
        let enabledControls = Set(
            SystemHUDControl.allCases.filter { control in
                availability.supports(control)
                    && SystemHUDSettings.isControlEnabled(
                        control,
                        defaults: defaults
                    )
            }
        )
        let interceptedControls = SystemHUDSettings.showsNativeControls(
            defaults: defaults
        ) ? [] : enabledControls

        interceptor.updateEnabledControls(interceptedControls)

        if accessibilityGranted, !interceptedControls.isEmpty {
            _ = interceptor.start()
            interceptionActive = interceptor.isRunning
        } else {
            interceptor.stop()
            interceptionActive = false
        }

        configurePassiveMonitoring(
            for: interceptionActive ? [] : enabledControls
        )
    }

    private func handle(_ event: MediaKeyEvent) {
        guard event.phase == .down else { return }
        guard !isScreenLocked else { return }

        let defaults = UserDefaults.standard
        let fine = event.isFineAdjustment
        let step = SystemHUDSettings.step(
            for: event.control,
            fine: fine,
            defaults: defaults
        )

        guard let result = backend.perform(
            event.control,
            action: event.action,
            step: step
        ) else {
            return
        }

        presentation = SystemHUDPresentation(
            control: event.control,
            level: result.level,
            isMuted: result.isMuted,
            isFineAdjustment: fine
        )

        if event.control == .volume,
           SystemHUDSettings.isAudioFeedbackEnabled(defaults: defaults),
           event.action != .mute {
            backend.playVolumeFeedback()
        }

        if event.control == .volume,
           SystemHUDSettings.isHapticFeedbackEnabled(defaults: defaults),
           event.action != .mute {
            NSHapticFeedbackManager.defaultPerformer.perform(
                .levelChange,
                performanceTime: .now
            )
        }

        scheduleHide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        let hideDelay: TimeInterval
        if presentation?.control == .volume {
            hideDelay = SoundHUDSettings.duration()
        } else {
            hideDelay = LightingHUDSettings.duration()
        }

        hideTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64(hideDelay * 1_000_000_000)
            )
            guard !Task.isCancelled else { return }
            self?.presentation = nil
        }
    }

    private func configurePassiveMonitoring(
        for controls: Set<SystemHUDControl>
    ) {
        guard controls != passiveControls || passiveMonitorTask == nil else {
            return
        }

        stopPassiveMonitoring()
        passiveControls = controls
        guard !controls.isEmpty else { return }

        refreshPassiveBaselines()
        lastVolumeOutputDeviceID = backend.volumeOutputDeviceID

        passiveMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard !Task.isCancelled else { return }
                self?.pollPassiveControls()
            }
        }
        passiveMonitoringActive = true
    }

    private func stopPassiveMonitoring() {
        passiveMonitorTask?.cancel()
        passiveMonitorTask = nil
        passiveControls.removeAll()
        lastPassiveStates.removeAll()
        lastVolumeOutputDeviceID = nil
        ignorePassiveVolumeUntil = 0
        passiveMonitoringActive = false
    }

    private func pollPassiveControls() {
        let now = ProcessInfo.processInfo.systemUptime
        let outputDeviceID = backend.volumeOutputDeviceID
        if outputDeviceID != lastVolumeOutputDeviceID {
            lastVolumeOutputDeviceID = outputDeviceID
            ignorePassiveVolumeUntil = now + 0.8
        }

        var latestChange: (SystemHUDControl, SystemControlResult)?

        for control in SystemHUDControl.allCases
        where passiveControls.contains(control) {
            guard let result = backend.currentState(control) else { continue }
            let state = PassiveState(
                level: result.level,
                isMuted: result.isMuted
            )

            if let previous = lastPassiveStates[control] {
                let levelChanged = abs(state.level - previous.level) >= 0.004
                let muteChanged = state.isMuted != previous.isMuted
                if levelChanged || muteChanged {
                    if control != .volume || now >= ignorePassiveVolumeUntil {
                        latestChange = (control, result)
                    }
                }
            }
            lastPassiveStates[control] = state
        }

        guard !isScreenLocked,
              !ignoresPassiveChanges,
              let (control, result) = latestChange else {
            return
        }
        presentation = SystemHUDPresentation(
            control: control,
            level: result.level,
            isMuted: result.isMuted,
            isFineAdjustment: false
        )
        scheduleHide()
    }

    private func refreshPassiveBaselines() {
        for control in passiveControls {
            guard let state = backend.currentState(control) else { continue }
            lastPassiveStates[control] = PassiveState(
                level: state.level,
                isMuted: state.isMuted
            )
        }
    }
}
