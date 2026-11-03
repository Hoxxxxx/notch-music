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

    private var monitorTask: Task<Void, Never>?
    private var distributedObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var defaultsObserver: NSObjectProtocol?
    private var unlockConfirmationTask: Task<Void, Never>?

    override init() {
        super.init()
        screenRecordingDetectionSupported = ScreenWatcherProbe.isAvailable
        isScreenLocked = Self.screenIsLocked()
        observeSystemChanges()
        observePreferenceChanges()
        startMonitoring()
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        unlockConfirmationTask?.cancel()
        unlockConfirmationTask = nil

        for observer in distributedObservers {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        distributedObservers.removeAll()

        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()

        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
            self.defaultsObserver = nil
        }
    }

    func refreshNow() {
        refreshSystemState()
    }

    private func startMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                self.refreshSystemState()
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
        }
    }

    private func refreshSystemState() {
        let defaults = UserDefaults.standard
        setScreenLocked(Self.screenIsLocked())

        if bool(for: SystemDetectionSettings.screenRecordingDetection, in: defaults) {
            update(\.isScreenRecording, ScreenWatcherProbe.isActive() ?? false)
        } else {
            update(\.isScreenRecording, false)
        }

        if bool(for: SystemDetectionSettings.focusDetection, in: defaults) {
            let activeModeIdentifier = Self.activeFocusModeIdentifier()
            update(\.focusName, Self.focusDisplayName(for: activeModeIdentifier))
            update(\.isFocusActive, activeModeIdentifier != nil)
        } else {
            update(\.focusName, "")
            update(\.isFocusActive, false)
        }

        update(
            \.isCapsLockOn,
            bool(for: SystemDetectionSettings.capsLockIndicator, in: defaults)
                && CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
        )

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
                    self?.refreshNow()
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

        guard !locked else {
            showsUnlockConfirmation = false
            return
        }

        showsUnlockConfirmation = true
        unlockConfirmationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.showsUnlockConfirmation = false
        }
    }

    private func observePreferenceChanges() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNow()
            }
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
        if #available(macOS 14.2, *) {
            return processIsUsingMicrophoneInput()
        }
        return deviceIsUsingMicrophoneInput()
    }

    @available(macOS 14.2, *)
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

    private static func deviceIsUsingMicrophoneInput() -> Bool {
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var devicesSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            0,
            nil,
            &devicesSize
        ) == noErr else {
            return false
        }

        var devices = [AudioObjectID](
            repeating: 0,
            count: Int(devicesSize) / MemoryLayout<AudioObjectID>.size
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            0,
            nil,
            &devicesSize,
            &devices
        ) == noErr else {
            return false
        }

        for device in devices {
            var streamsAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamsSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(
                device,
                &streamsAddress,
                0,
                nil,
                &streamsSize
            ) == noErr, streamsSize > 0 else {
                continue
            }

            let bufferList = UnsafeMutableRawPointer.allocate(
                byteCount: Int(streamsSize),
                alignment: MemoryLayout<AudioBufferList>.alignment
            )
            defer { bufferList.deallocate() }

            guard AudioObjectGetPropertyData(
                device,
                &streamsAddress,
                0,
                nil,
                &streamsSize,
                bufferList
            ) == noErr else {
                continue
            }

            let buffers = UnsafeMutableAudioBufferListPointer(
                bufferList.assumingMemoryBound(to: AudioBufferList.self)
            )
            let inputChannels = buffers.reduce(0) {
                $0 + Int($1.mNumberChannels)
            }
            guard inputChannels > 0 else { continue }

            var runningAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var isRunning: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(
                device,
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
