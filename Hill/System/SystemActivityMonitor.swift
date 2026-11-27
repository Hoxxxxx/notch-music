import AppKit
import Combine
import CoreAudio
import CoreGraphics
import CoreMediaIO
import Darwin
import Foundation
import SwiftUI

enum SystemDetectionSettings {
    static let screenRecordingDetection = "NotchMusic.screenRecordingDetectionEnabled"
    static let screenRecordingIndicator = "NotchMusic.screenRecordingIndicatorEnabled"
    static let focusDetection = "NotchMusic.focusDetectionEnabled"
    static let focusIndicator = "NotchMusic.focusIndicatorEnabled"
    static let focusLabel = "NotchMusic.focusLabelEnabled"
    static let focusCompactHint = "NotchMusic.focusCompactHintEnabled"
    static let capsLockIndicator = "NotchMusic.capsLockIndicatorEnabled"
    static let capsLockLabel = "NotchMusic.capsLockLabelEnabled"
    static let capsLockColor = "NotchMusic.capsLockColor"
    static let cameraDetection = "NotchMusic.cameraDetectionEnabled"
    static let microphoneDetection = "NotchMusic.microphoneDetectionEnabled"
}

enum CapsLockIndicatorColor: String, CaseIterable, Identifiable {
    case blue
    case purple
    case white

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blue:
            return "蓝色"
        case .purple:
            return "紫色"
        case .white:
            return "白色"
        }
    }

    var color: Color {
        switch self {
        case .blue:
            return Color(red: 0.25, green: 0.56, blue: 1.0)
        case .purple:
            return Color(red: 0.67, green: 0.42, blue: 1.0)
        case .white:
            return .white
        }
    }
}

@MainActor
final class SystemActivityMonitor: NSObject, ObservableObject {
    @Published private(set) var isScreenRecording = false
    @Published private(set) var screenRecordingDetectionSupported = true
    @Published private(set) var isFocusActive = false
    @Published private(set) var focusName = ""
    @Published private(set) var isCapsLockOn = false
    @Published private(set) var isCameraActive = false
    @Published private(set) var isMicrophoneActive = false
    @Published private(set) var isScreenLocked = false
    @Published private(set) var showsUnlockConfirmation = false
    @Published private(set) var showsUnlockFailure = false

    private var monitorTask: Task<Void, Never>?
    private var capsLockTask: Task<Void, Never>?
    private var lockStateTask: Task<Void, Never>?
    private var distributedObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var defaultsObserver: DefaultsKeyObserver?
    private var unlockConfirmationTask: Task<Void, Never>?
    private var unlockFailureTask: Task<Void, Never>?
    private var unlockAttemptLog: Process?
    private var unlockTransitionGraceDeadline = Date.distantPast

    override init() {
        super.init()
        screenRecordingDetectionSupported = ScreenWatcherProbe.isAvailable
        isScreenLocked = Self.screenIsLocked()
        if isScreenLocked {
            startUnlockAttemptMonitor()
            startLockStateMonitoring()
        }
        observeSystemChanges()
        observePreferenceChanges()
        refreshFocusState()
        startMonitoring()
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        stopLockStateMonitoring()
        unlockConfirmationTask?.cancel()
        unlockConfirmationTask = nil
        unlockFailureTask?.cancel()
        unlockFailureTask = nil
        stopUnlockAttemptMonitor()

        for observer in distributedObservers {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        distributedObservers.removeAll()

        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()

        defaultsObserver = nil
    }

    func refreshNow() {
        refreshSystemState()
        refreshFocusState()
    }

    private func startMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        capsLockTask?.cancel()
        capsLockTask = nil
        guard !isScreenLocked else { return }

        monitorTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                self.refreshSystemState()
                try? await Task.sleep(for: .seconds(1))
            }
        }

        capsLockTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.refreshCapsLockState()
                let isEnabled = self.bool(
                    for: SystemDetectionSettings.capsLockIndicator,
                    in: .standard
                )
                try? await Task.sleep(
                    for: .milliseconds(isEnabled ? 200 : 2_000)
                )
            }
        }
    }

    private func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        capsLockTask?.cancel()
        capsLockTask = nil
    }

    private func refreshSystemState() {
        let defaults = UserDefaults.standard
        if Date() >= unlockTransitionGraceDeadline {
            setScreenLocked(Self.screenIsLocked())
        }
        guard !isScreenLocked else { return }

        if bool(for: SystemDetectionSettings.screenRecordingDetection, in: defaults) {
            update(\.isScreenRecording, ScreenWatcherProbe.isActive() ?? false)
        } else {
            update(\.isScreenRecording, false)
        }

        refreshCapsLockState()

        if bool(for: SystemDetectionSettings.cameraDetection, in: defaults) {
            update(\.isCameraActive, Self.cameraIsActive())
        } else {
            update(\.isCameraActive, false)
        }

        if bool(for: SystemDetectionSettings.microphoneDetection, in: defaults) {
            update(\.isMicrophoneActive, Self.microphoneIsActive())
        } else {
            update(\.isMicrophoneActive, false)
        }
    }

    private func refreshFocusState() {
        let defaults = UserDefaults.standard
        guard !isScreenLocked else {
            update(\.focusName, "")
            update(\.isFocusActive, false)
            return
        }

        if bool(for: SystemDetectionSettings.focusDetection, in: defaults) {
            let activeModeIdentifier = Self.activeFocusModeIdentifier()
            update(\.focusName, Self.focusDisplayName(for: activeModeIdentifier))
            update(\.isFocusActive, activeModeIdentifier != nil)
        } else {
            update(\.focusName, "")
            update(\.isFocusActive, false)
        }
    }

    private func refreshCapsLockState() {
        update(
            \.isCapsLockOn,
            bool(
                for: SystemDetectionSettings.capsLockIndicator,
                in: .standard
            ) && CGEventSource.flagsState(.combinedSessionState)
                .contains(.maskAlphaShift)
        )
    }

    private func observeSystemChanges() {
        let focusNames = [
            "com.apple.notificationcenterui.dndState.changed",
            "com.apple.donotdisturb.state.changed"
        ]

        for name in focusNames {
            let observer = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshFocusState()
                }
            }
            distributedObservers.append(observer)
        }

        let lockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setScreenLocked(true)
            }
        }
        distributedObservers.append(lockObserver)

        let unlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setScreenLocked(false)
            }
        }
        distributedObservers.append(unlockObserver)

        for name in [
            NSWorkspace.sessionDidResignActiveNotification,
            NSWorkspace.sessionDidBecomeActiveNotification
        ] {
            let observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.setScreenLocked(Self.screenIsLocked())
                }
            }
            workspaceObservers.append(observer)
        }
    }

    private func setScreenLocked(_ locked: Bool) {
        guard isScreenLocked != locked else { return }

        isScreenLocked = locked
        unlockConfirmationTask?.cancel()
        unlockConfirmationTask = nil
        unlockFailureTask?.cancel()
        unlockFailureTask = nil
        showsUnlockFailure = false

        guard !locked else {
            showsUnlockConfirmation = false
            stopMonitoring()
            startUnlockAttemptMonitor()
            startLockStateMonitoring()
            return
        }

        stopLockStateMonitoring()
        unlockTransitionGraceDeadline = Date().addingTimeInterval(1)
        stopUnlockAttemptMonitor()
        startMonitoring()
        refreshFocusState()
        showsUnlockConfirmation = true
        unlockConfirmationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.showsUnlockConfirmation = false
        }
    }

    private func startLockStateMonitoring() {
        guard lockStateTask == nil else { return }

        lockStateTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.setScreenLocked(Self.screenIsLocked())
                if !self.isScreenLocked { return }
            }
        }
    }

    private func stopLockStateMonitoring() {
        lockStateTask?.cancel()
        lockStateTask = nil
    }

    private func startUnlockAttemptMonitor() {
        guard unlockAttemptLog == nil else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "stream",
            "--style",
            "compact",
            "--predicate",
            #"process == "loginwindow" AND eventMessage CONTAINS "INCORRECT password""#
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let text = String(data: data, encoding: .utf8),
                  text.split(separator: "\n").contains(where: {
                      $0.contains("loginwindow[")
                          && $0.contains("INCORRECT password")
                  }) else {
                return
            }
            Task { @MainActor in
                self?.registerUnlockFailure()
            }
        }

        do {
            try process.run()
            unlockAttemptLog = process
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
    }

    private func stopUnlockAttemptMonitor() {
        guard let process = unlockAttemptLog else { return }
        unlockAttemptLog = nil
        if process.isRunning {
            process.terminate()
        }
    }

    private func registerUnlockFailure() {
        guard isScreenLocked else { return }

        showsUnlockFailure = true
        unlockFailureTask?.cancel()
        unlockFailureTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.showsUnlockFailure = false
        }
    }

    private func observePreferenceChanges() {
        defaultsObserver = DefaultsKeyObserver(
            keys: [
                SystemDetectionSettings.screenRecordingDetection,
                SystemDetectionSettings.focusDetection,
                SystemDetectionSettings.capsLockIndicator,
                SystemDetectionSettings.cameraDetection,
                SystemDetectionSettings.microphoneDetection
            ]
        ) { [weak self] in
            self?.refreshNow()
        }
    }

    private func bool(for key: String, in defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: key) != nil else { return true }
        return defaults.bool(forKey: key)
    }

    private func update<Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<SystemActivityMonitor, Value>,
        _ value: Value
    ) {
        guard self[keyPath: keyPath] != value else { return }
        self[keyPath: keyPath] = value
    }

    private static func activeFocusModeIdentifier() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stores = root["data"] as? [[String: Any]] else {
            return nil
        }

        for store in stores {
            guard let assertions = store["storeAssertionRecords"] as? [[String: Any]] else {
                continue
            }

            for assertion in assertions {
                guard let details = assertion["assertionDetails"] as? [String: Any],
                      let identifier = details["assertionDetailsModeIdentifier"] as? String,
                      !identifier.isEmpty else {
                    continue
                }
                return identifier
            }
        }

        return nil
    }

    private static func focusDisplayName(for identifier: String?) -> String {
        guard let identifier, !identifier.isEmpty else { return "" }
        let value = identifier.lowercased()

        if value.contains("sleep") {
            return "睡眠"
        }
        if value.contains("work") {
            return "工作"
        }
        if value.contains("personal") {
            return "个人"
        }
        if value.contains("driving") {
            return "驾驶"
        }
        if value.contains("fitness") || value.contains("workout") {
            return "健身"
        }
        if value.contains("gaming") || value.contains("game") {
            return "游戏"
        }
        if value.contains("reading") {
            return "阅读"
        }
        if value.contains("mindfulness") {
            return "正念"
        }
        if value == "com.apple.donotdisturb.mode.default" {
            return "勿扰模式"
        }
        return "专注模式"
    }

    private static func screenIsLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let locked = session["CGSSessionScreenIsLocked"] as? NSNumber else {
            return false
        }
        return locked.boolValue
    }

    private static func cameraIsActive() -> Bool {
        var devicesAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var devicesSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject),
            &devicesAddress,
            0,
            nil,
            &devicesSize
        ) == noErr else {
            return false
        }

        var devices = [CMIOObjectID](
            repeating: 0,
            count: Int(devicesSize) / MemoryLayout<CMIOObjectID>.size
        )
        guard CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &devicesAddress,
            0,
            nil,
            devicesSize,
            &devicesSize,
            &devices
        ) == noErr else {
            return false
        }

        for device in devices {
            var runningAddress = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(
                    kCMIODevicePropertyDeviceIsRunningSomewhere
                ),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )
            var isRunning: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            if CMIOObjectGetPropertyData(
                device,
                &runningAddress,
                0,
                nil,
                runningSize,
                &runningSize,
                &isRunning
            ) == noErr, isRunning != 0 {
                return true
            }
        }

        return false
    }

    private static func microphoneIsActive() -> Bool {
        processIsUsingMicrophoneInput()
    }

    private static func processIsUsingMicrophoneInput() -> Bool {
        var processesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var processesSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &processesAddress,
            0,
            nil,
            &processesSize
        ) == noErr else {
            return false
        }

        var processes = [AudioObjectID](
            repeating: 0,
            count: Int(processesSize) / MemoryLayout<AudioObjectID>.size
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &processesAddress,
            0,
            nil,
            &processesSize,
            &processes
        ) == noErr else {
            return false
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier

        for process in processes {
            var pidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyPID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            guard AudioObjectGetPropertyData(
                process,
                &pidAddress,
                0,
                nil,
                &pidSize,
                &pid
            ) == noErr, pid != currentPID else {
                continue
            }

            if isAmbientSpeechProcess(process) {
                continue
            }

            var runningAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningInput,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var isRunning: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(
                process,
                &runningAddress,
                0,
                nil,
                &runningSize,
                &isRunning
            ) == noErr, isRunning != 0 {
                return true
            }
        }

        return false
    }

    private static func isAmbientSpeechProcess(
        _ process: AudioObjectID
    ) -> Bool {
        var bundleAddress = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var bundleID: CFString = "" as CFString
        var bundleSize = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &bundleID) { pointer in
            AudioObjectGetPropertyData(
                process,
                &bundleAddress,
                0,
                nil,
                &bundleSize,
                pointer
            )
        }
        guard status == noErr else { return false }
        return (bundleID as String) == "com.apple.CoreSpeech"
    }

}

private enum ScreenWatcherProbe {
    private typealias MainConnectionFunction = @convention(c) () -> UInt32
    private typealias IsWatcherPresentFunction = @convention(c) (UInt32) -> UInt32

    private static let functions: (
        mainConnection: MainConnectionFunction,
        isWatcherPresent: IsWatcherPresentFunction
    )? = {
        guard let handle = dlopen(nil, RTLD_LAZY),
              let mainSymbol = dlsym(handle, "CGSMainConnectionID"),
              let watcherSymbol = dlsym(handle, "CGSIsScreenWatcherPresent") else {
            return nil
        }

        return (
            unsafeBitCast(mainSymbol, to: MainConnectionFunction.self),
            unsafeBitCast(watcherSymbol, to: IsWatcherPresentFunction.self)
        )
    }()

    static var isAvailable: Bool {
        functions != nil
    }

    static func isActive() -> Bool? {
        guard let functions else { return nil }
        return functions.isWatcherPresent(functions.mainConnection()) != 0
    }
}
