import AppKit
import ApplicationServices
import Combine
import Foundation

enum SystemHUDStyle: String, CaseIterable, Identifiable {
    case island
    case customOSD
    case vertical
    case circular

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .island:
            return "灵动岛"
        case .customOSD:
            return "自定义 OSD"
        case .vertical:
            return "垂直条"
        case .circular:
            return "圆形"
        }
    }

    static let storageKey = "NotchMusic.systemHUDStyle"
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
            return "亮度"
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

    static func isColoredVolumeEnabled(
        defaults: UserDefaults = .standard
    ) -> Bool {
        bool(
            for: coloredVolumeEnabled,
            defaultValue: true,
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
            fallback = fine ? 2 : 6
        case .displayBrightness, .keyboardBrightness:
            key = fine ? brightnessFineStep : brightnessStep
            fallback = fine ? 2 : 6
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
    private var passiveControls = Set<SystemHUDControl>()
    private var lastPassiveStates: [SystemHUDControl: PassiveState] = [:]

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
        interceptor.stop()
        stopPassiveMonitoring()
        interceptionActive = false
        presentation = nil

        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
            self.defaultsObserver = nil
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

        scheduleHide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_350_000_000)
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

        for control in controls {
            if let state = backend.currentState(control) {
                lastPassiveStates[control] = PassiveState(
                    level: state.level,
                    isMuted: state.isMuted
                )
            }
        }

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
        passiveMonitoringActive = false
    }

    private func pollPassiveControls() {
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
                    latestChange = (control, result)
                }
            }
            lastPassiveStates[control] = state
        }

        guard let (control, result) = latestChange else { return }
        presentation = SystemHUDPresentation(
            control: control,
            level: result.level,
            isMuted: result.isMuted,
            isFineAdjustment: false
        )
        scheduleHide()
    }
}
