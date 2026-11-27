import Accelerate
import AppKit
import AudioToolbox
import CoreAudio
import Darwin
import Foundation

@MainActor
final class AppVolumeMixer: ObservableObject {
    struct OutputDevice: Identifiable, Equatable {
        let id: String
        let uid: String
        let name: String
        let isDefault: Bool
        let canBeDefaultOutput: Bool
        fileprivate let audioObjectID: AudioObjectID
    }

    struct AppRow: Identifiable, Equatable {
        let id: String
        let name: String
        let icon: NSImage?
        let isPlaying: Bool
        var volume: Double
        var isMuted: Bool
        var outputDeviceUID: String?
        var outputDeviceUnavailable: Bool

        static func == (lhs: AppRow, rhs: AppRow) -> Bool {
            lhs.id == rhs.id
                && lhs.name == rhs.name
                && lhs.isPlaying == rhs.isPlaying
                && lhs.volume == rhs.volume
                && lhs.isMuted == rhs.isMuted
                && lhs.outputDeviceUID == rhs.outputDeviceUID
                && lhs.outputDeviceUnavailable == rhs.outputDeviceUnavailable
        }
    }

    @Published private(set) var apps: [AppRow] = []
    @Published private(set) var outputDevices: [OutputDevice] = []
    @Published private(set) var tapFailed = false

    private struct AudioApp {
        let id: String
        let name: String
        let icon: NSImage?
        let objects: [AudioObjectID]
        let isPlaying: Bool
    }

    private static let volumesKey = "NotchMusic.appVolumeLevels"
    private static let mutedKey = "NotchMusic.appVolumeMuted"
    private static let outputDevicesKey = "NotchMusic.appOutputDevices"

    private var engines: [String: MixerEngine] = [:]
    private var volumes: [String: Double]
    private var mutedIDs: Set<String>
    private var outputDeviceUIDs: [String: String]
    private var audioAppsByID: [String: AudioApp] = [:]
    private var failedAt: [String: Date] = [:]
    private var failedEngineIDs: Set<String> = []
    private var pollTask: Task<Void, Never>?
    private var persistTask: Task<Void, Never>?
    private var outputUID: String?
    private var isRunning = false

    init() {
        let stored = UserDefaults.standard.dictionary(
            forKey: Self.volumesKey
        ) ?? [:]
        volumes = stored.compactMapValues { value in
            if let number = value as? NSNumber {
                return number.doubleValue
            }
            if let text = value as? String {
                return Double(text)
            }
            return nil
        }
        mutedIDs = Set(
            UserDefaults.standard.stringArray(forKey: Self.mutedKey) ?? []
        )
        outputDeviceUIDs = UserDefaults.standard.dictionary(
            forKey: Self.outputDevicesKey
        )?.compactMapValues { $0 as? String } ?? [:]
    }

    func startAtLaunchIfNeeded() {
        guard hasPersistedOverrides else { return }
        start()
    }

    func start(refreshImmediately: Bool = false) {
        guard !isRunning else { return }
        isRunning = true

        if refreshImmediately {
            refresh()
        }

        pollTask = Task { [weak self] in
            if !refreshImmediately {
                self?.refresh()
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    func stop() {
        isRunning = false
        pollTask?.cancel()
        pollTask = nil
        persistTask?.cancel()
        persistTask = nil
        persistVolumes()
        stopAllEngines()
        apps = []
    }

    func setVolume(_ volume: Double, for id: String) {
        let clamped = min(max(volume, 0), 1)
        volumes[id] = clamped
        if mutedIDs.remove(id) != nil {
            persistMutes()
        }
        schedulePersistVolumes()

        if let index = apps.firstIndex(where: { $0.id == id }) {
            apps[index].volume = clamped
            apps[index].isMuted = false
        }

        applyVolume(for: id)
    }

    func toggleMute(for id: String) {
        if mutedIDs.contains(id) {
            mutedIDs.remove(id)
        } else {
            mutedIDs.insert(id)
        }
        persistMutes()

        if let index = apps.firstIndex(where: { $0.id == id }) {
            apps[index].isMuted = mutedIDs.contains(id)
        }

        applyVolume(for: id)
    }

    func setSystemOutputDevice(_ uid: String) {
        guard let device = outputDevices.first(where: {
            $0.uid == uid && $0.canBeDefaultOutput
        }) else {
            return
        }

        var deviceID = device.audioObjectID
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioObjectID>.size),
            &deviceID
        ) == noErr else {
            return
        }

        outputUID = uid
        for (id, engine) in engines
        where selectedOutputUID(for: id) == nil {
            engine.stop()
            engines.removeValue(forKey: id)
        }
        refresh()
    }

    func setOutputDevice(_ uid: String?, for id: String) {
        guard outputDeviceUIDs[id] != uid else { return }
        if let uid {
            outputDeviceUIDs[id] = uid
        } else {
            outputDeviceUIDs.removeValue(forKey: id)
        }
        UserDefaults.standard.set(
            outputDeviceUIDs,
            forKey: Self.outputDevicesKey
        )

        if let index = apps.firstIndex(where: { $0.id == id }) {
            let selected = selectedOutputUID(for: id)
            apps[index].outputDeviceUID = selected
            apps[index].outputDeviceUnavailable =
                uid != nil && selected == nil
        }

        stopEngine(for: id)
        applyVolume(for: id)
    }

    func openAudioPermissionSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func refresh() {
        let snapshot = Self.audioApps()
        audioAppsByID = Dictionary(
            uniqueKeysWithValues: snapshot.map { ($0.id, $0) }
        )
        let newOutputUID = Self.defaultOutputDeviceUID()
        let devices = Self.outputDevices(defaultUID: newOutputUID)
        if devices != outputDevices {
            outputDevices = devices
        }
        if newOutputUID != outputUID {
            outputUID = newOutputUID
            for (id, engine) in engines
            where selectedOutputUID(for: id) == nil {
                engine.stop()
                engines.removeValue(forKey: id)
            }
        }

        var rows: [AppRow] = []
        for app in snapshot {
            let volume = volumes[app.id] ?? 1
            let isMuted = mutedIDs.contains(app.id)
            let selectedOutputUID = selectedOutputUID(for: app.id)
            rows.append(
                AppRow(
                    id: app.id,
                    name: app.name,
                    icon: app.icon,
                    isPlaying: app.isPlaying,
                    volume: volume,
                    isMuted: isMuted,
                    outputDeviceUID: selectedOutputUID,
                    outputDeviceUnavailable:
                        outputDeviceUIDs[app.id] != nil
                        && selectedOutputUID == nil
                )
            )
        }
        rows.sort {
            if $0.isPlaying != $1.isPlaying {
                return $0.isPlaying
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        if rows != apps {
            apps = rows
        }

        for (id, engine) in engines {
            guard let app = snapshot.first(where: { $0.id == id }),
                  app.objects == engine.objects,
                  let targetOutputUID = targetOutputUID(for: id),
                  engine.outputDeviceUID == targetOutputUID,
                  requiresEngine(for: id) else {
                engine.stop()
                engines.removeValue(forKey: id)
                continue
            }
            engine.volume = Float(effectiveVolume(for: id))
        }

        for app in snapshot where requiresEngine(for: app.id) {
            if engines[app.id] != nil {
                continue
            }
            ensureEngine(for: app)
        }

        let requiredIDs = Set(
            snapshot
                .filter { requiresEngine(for: $0.id) }
                .map(\.id)
        )
        failedEngineIDs.formIntersection(requiredIDs)
        failedAt = failedAt.filter { requiredIDs.contains($0.key) }
        updateTapFailed()
    }

    private func ensureEngine(for app: AudioApp) {
        guard !app.objects.isEmpty else { return }
        if let failed = failedAt[app.id],
           Date().timeIntervalSince(failed) < 5 {
            return
        }
        guard let targetOutputUID = targetOutputUID(for: app.id) else {
            return
        }

        guard let engine = MixerEngine(
            objects: app.objects,
            outputUID: targetOutputUID
        ) else {
            failedAt[app.id] = Date()
            failedEngineIDs.insert(app.id)
            updateTapFailed()
            return
        }

        engine.volume = Float(effectiveVolume(for: app.id))
        engines[app.id] = engine
        failedAt[app.id] = nil
        failedEngineIDs.remove(app.id)
        updateTapFailed()
    }

    private func updateTapFailed() {
        let failed = !failedEngineIDs.isEmpty
        if tapFailed != failed {
            tapFailed = failed
        }
    }

    private func stopEngine(for id: String) {
        engines.removeValue(forKey: id)?.stop()
    }

    private func stopAllEngines() {
        for engine in engines.values {
            engine.stop()
        }
        engines.removeAll()
    }

    private func effectiveVolume(for id: String) -> Double {
        mutedIDs.contains(id) ? 0 : (volumes[id] ?? 1)
    }

    private var hasPersistedOverrides: Bool {
        volumes.values.contains { $0 < 0.995 }
            || !mutedIDs.isEmpty
            || !outputDeviceUIDs.isEmpty
    }

    private func selectedOutputUID(for id: String) -> String? {
        guard let uid = outputDeviceUIDs[id],
              outputDevices.contains(where: { $0.uid == uid }) else {
            return nil
        }
        return uid
    }

    private func targetOutputUID(for id: String) -> String? {
        selectedOutputUID(for: id) ?? outputUID
    }

    private func requiresEngine(for id: String) -> Bool {
        selectedOutputUID(for: id) != nil
            || effectiveVolume(for: id) < 0.995
    }

    private func applyVolume(for id: String) {
        let target = effectiveVolume(for: id)
        guard requiresEngine(for: id),
              let targetOutputUID = targetOutputUID(for: id) else {
            stopEngine(for: id)
            return
        }
        if let engine = engines[id],
           engine.outputDeviceUID == targetOutputUID {
            engine.volume = Float(target)
            return
        }
        stopEngine(for: id)
        if let app = audioAppsByID[id] {
            ensureEngine(for: app)
        }
    }

    private func persistVolumes() {
        UserDefaults.standard.set(volumes, forKey: Self.volumesKey)
    }

    private func schedulePersistVolumes() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            self?.persistVolumes()
        }
    }

    private func persistMutes() {
        UserDefaults.standard.set(
            Array(mutedIDs),
            forKey: Self.mutedKey
        )
    }

    private static func audioApps() -> [AudioApp] {
        let objects = processObjects() ?? []

        var grouped: [
            String: (
                app: NSRunningApplication,
                objects: [AudioObjectID],
                playing: Bool
            )
        ] = [:]
        for object in objects {
            var pid: pid_t = 0
            guard read(object, kAudioProcessPropertyPID, &pid),
                  pid > 0,
                  pid != ProcessInfo.processInfo.processIdentifier else {
                continue
            }

            let bundleID = readString(
                object,
                kAudioProcessPropertyBundleID
            )
            var running: UInt32 = 0
            _ = read(
                object,
                kAudioProcessPropertyIsRunningOutput,
                &running
            )
            let app = owningApp(bundleID: bundleID, pid: pid)
            guard let app,
                  let key = app.bundleIdentifier,
                  key != Bundle.main.bundleIdentifier else {
                continue
            }

            var entry = grouped[key] ?? (app, [], false)
            entry.objects.append(object)
            entry.playing = entry.playing || running != 0
            grouped[key] = entry
        }

        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  !app.isTerminated,
                  let key = app.bundleIdentifier,
                  key != Bundle.main.bundleIdentifier,
                  grouped[key] == nil else {
                continue
            }
            grouped[key] = (app, [], false)
        }

        return grouped.compactMap { key, value in
            return AudioApp(
                id: key,
                name: value.app.localizedName ?? key,
                icon: value.app.icon,
                objects: value.objects.sorted(),
                isPlaying: value.playing
            )
        }
    }

    private static func owningApp(
        bundleID: String?,
        pid: pid_t
    ) -> NSRunningApplication? {
        guard let bundleID else { return nil }

        var candidates = [bundleID]
        var candidate = bundleID
        while let separator = candidate.lastIndex(of: ".") {
            candidate = String(candidate[..<separator])
            candidates.append(candidate)
        }

        for candidate in candidates {
            if let app = NSRunningApplication
                .runningApplications(withBundleIdentifier: candidate)
                .first(where: { $0.activationPolicy == .regular }) {
                return app
            }
        }

        guard let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy == .regular else {
            return nil
        }
        return app
    }

    private static func processObjects() -> [AudioObjectID]? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(
            system,
            &address,
            0,
            nil,
            &size
        ) == noErr else {
            return nil
        }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }

        var objects = [AudioObjectID](
            repeating: AudioObjectID(kAudioObjectUnknown),
            count: count
        )
        guard AudioObjectGetPropertyData(
            system,
            &address,
            0,
            nil,
            &size,
            &objects
        ) == noErr else {
            return nil
        }
        return objects
    }

    private static func read<T>(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        _ value: inout T,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(
            object,
            &address,
            0,
            nil,
            &size,
            &value
        ) == noErr
    }

    private static func readString(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(
            object,
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

    private static func outputDevices(
        defaultUID: String?
    ) -> [OutputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(
            system,
            &address,
            0,
            nil,
            &size
        ) == noErr else {
            return []
        }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }

        var ids = [AudioObjectID](
            repeating: AudioObjectID(kAudioObjectUnknown),
            count: count
        )
        guard AudioObjectGetPropertyData(
            system,
            &address,
            0,
            nil,
            &size,
            &ids
        ) == noErr else {
            return []
        }

        var devices: [OutputDevice] = []
        for id in ids {
            guard !outputStreams(id).isEmpty else { continue }

            var isAlive: UInt32 = 1
            if read(id, kAudioDevicePropertyDeviceIsAlive, &isAlive),
               isAlive == 0 {
                continue
            }

            var isHidden: UInt32 = 0
            if read(id, kAudioDevicePropertyIsHidden, &isHidden),
               isHidden != 0 {
                continue
            }

            guard let uid = readString(
                id,
                kAudioDevicePropertyDeviceUID
            ), !uid.isEmpty else {
                continue
            }
            guard !uid.hasPrefix("NotchMusic.Mixer.") else { continue }

            let name = readString(id, kAudioObjectPropertyName) ?? uid
            guard !name.hasPrefix("NotchMusic Mixer") else { continue }

            var canBeDefault: UInt32 = 0
            _ = read(
                id,
                kAudioDevicePropertyDeviceCanBeDefaultDevice,
                &canBeDefault,
                scope: kAudioObjectPropertyScopeOutput
            )

            devices.append(
                OutputDevice(
                    id: uid,
                    uid: uid,
                    name: name,
                    isDefault: uid == defaultUID,
                    canBeDefaultOutput: canBeDefault != 0,
                    audioObjectID: id
                )
            )
        }

        return devices.sorted {
            if $0.isDefault != $1.isDefault {
                return $0.isDefault
            }
            return $0.name.localizedStandardCompare($1.name)
                == .orderedAscending
        }
    }

    private static func outputStreams(
        _ deviceID: AudioObjectID
    ) -> [AudioStreamID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            deviceID,
            &address,
            0,
            nil,
            &size
        ) == noErr,
        size >= MemoryLayout<AudioStreamID>.size else {
            return []
        }

        var streams = [AudioStreamID](
            repeating: AudioStreamID(kAudioObjectUnknown),
            count: Int(size) / MemoryLayout<AudioStreamID>.size
        )
        guard AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &streams
        ) == noErr else {
            return []
        }
        return Array(
            streams.prefix(Int(size) / MemoryLayout<AudioStreamID>.size)
        )
    }

    private static func defaultOutputDeviceUID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        ) == noErr, device != kAudioObjectUnknown else {
            return nil
        }

        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(
            device,
            &uidAddress,
            0,
            nil,
            &uidSize,
            &uid
        ) == noErr, let uid else {
            return nil
        }
        return uid.takeRetainedValue() as String
    }
}

private final class MixerEngine: @unchecked Sendable {
    let objects: [AudioObjectID]
    let outputDeviceUID: String

    private let gain = AtomicFloat(1)
    private var tapChannels = 0
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var isStopped = false

    var volume: Float {
        get { gain.value }
        set { gain.value = min(max(newValue, 0), 1) }
    }

    init?(objects: [AudioObjectID], outputUID: String) {
        guard !objects.isEmpty else { return nil }

        self.objects = objects
        self.outputDeviceUID = outputUID

        let description = CATapDescription(
            stereoMixdownOfProcesses: objects
        )
        description.name = "NotchMusic Mixer"
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped

        var tap = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr,
              tap != kAudioObjectUnknown else {
            stop()
            return nil
        }
        tapID = tap

        guard let format = Self.tapFormat(tap),
              format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mFormatFlags & kAudioFormatFlagIsPacked != 0,
              format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0,
              format.mFormatFlags & kAudioFormatFlagIsBigEndian
                == kAudioFormatFlagsNativeEndian,
              format.mBitsPerChannel == 32,
              format.mFramesPerPacket == 1,
              format.mChannelsPerFrame > 0,
              format.mBytesPerFrame
                == format.mChannelsPerFrame * 4 else {
            stop()
            return nil
        }
        tapChannels = Int(format.mChannelsPerFrame)

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "NotchMusic Mixer",
            kAudioAggregateDeviceUIDKey: "NotchMusic.Mixer.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true
                ]
            ]
        ]

        var device = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(
            aggregate as CFDictionary,
            &device
        ) == noErr, device != kAudioObjectUnknown else {
            stop()
            return nil
        }
        aggregateID = device

        let tapChannelCount = tapChannels
        let gainBox = gain
        var proc: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(
            &proc,
            aggregateID,
            nil
        ) { _, input, _, output, _ in
            Self.render(
                input: input,
                output: output,
                channels: tapChannelCount,
                gain: gainBox.value
            )
        }

        guard status == noErr, let proc else {
            stop()
            return nil
        }
        ioProcID = proc

        guard AudioDeviceStart(aggregateID, proc) == noErr else {
            stop()
            return nil
        }
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true

        if let ioProcID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil

        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = kAudioObjectUnknown
        }

        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
    }

    deinit {
        stop()
    }

    private static func tapFormat(
        _ tapID: AudioObjectID
    ) -> AudioStreamBasicDescription? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(
            tapID,
            &address,
            0,
            nil,
            &size,
            &format
        ) == noErr else {
            return nil
        }
        return format
    }

    private static func render(
        input: UnsafePointer<AudioBufferList>?,
        output: UnsafeMutablePointer<AudioBufferList>?,
        channels: Int,
        gain: Float
    ) {
        guard let output else { return }
        let outputBuffers = UnsafeMutableAudioBufferListPointer(output)

        guard let input, channels > 0 else {
            silence(outputBuffers)
            return
        }

        let inputBuffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: input)
        )
        guard let tapIndex = tapBufferIndex(
            in: inputBuffers,
            tapChannels: channels
        ) else {
            silence(outputBuffers)
            return
        }

        let source = inputBuffers[tapIndex]
        let sourceChannels = Int(source.mNumberChannels)
        guard sourceChannels > 0,
              let samples = source.mData?
                .assumingMemoryBound(to: Float.self) else {
            silence(outputBuffers)
            return
        }
        let sourceFrames = Int(source.mDataByteSize)
            / (MemoryLayout<Float>.size * sourceChannels)
        guard sourceFrames > 0 else {
            silence(outputBuffers)
            return
        }

        var channelOffset = 0

        for buffer in outputBuffers {
            let outChannels = Int(buffer.mNumberChannels)
            guard outChannels > 0 else {
                continue
            }
            guard let data = buffer.mData?
                .assumingMemoryBound(to: Float.self) else {
                channelOffset += outChannels
                continue
            }

            let frames = Int(buffer.mDataByteSize)
                / (MemoryLayout<Float>.size * outChannels)
            memset(data, 0, Int(buffer.mDataByteSize))
            let writableFrames = min(sourceFrames, frames)
            guard writableFrames > 0 else {
                channelOffset += outChannels
                continue
            }

            if outChannels == 1, sourceChannels > 1 {
                var scale = gain / Float(sourceChannels)
                vDSP_vsmul(
                    samples,
                    vDSP_Stride(sourceChannels),
                    &scale,
                    data,
                    1,
                    vDSP_Length(writableFrames)
                )
                for channel in 1..<sourceChannels {
                    vDSP_vsma(
                        samples + channel,
                        vDSP_Stride(sourceChannels),
                        &scale,
                        data,
                        1,
                        data,
                        1,
                        vDSP_Length(writableFrames)
                    )
                }
                channelOffset += outChannels
                continue
            }

            for channel in 0..<outChannels {
                guard let sourceChannel = Self.sourceChannel(
                    for: channelOffset + channel,
                    sourceChannels: sourceChannels
                ) else {
                    continue
                }
                var scale = gain
                vDSP_vsmul(
                    samples + sourceChannel,
                    vDSP_Stride(sourceChannels),
                    &scale,
                    data + channel,
                    vDSP_Stride(outChannels),
                    vDSP_Length(writableFrames)
                )
            }
            channelOffset += outChannels
        }
    }

    private static func sourceChannel(
        for outputChannel: Int,
        sourceChannels: Int
    ) -> Int? {
        if outputChannel < sourceChannels {
            return outputChannel
        }
        if sourceChannels == 1, outputChannel == 1 {
            return 0
        }
        return nil
    }

    private static func tapBufferIndex(
        in buffers: UnsafeMutableAudioBufferListPointer,
        tapChannels: Int
    ) -> Int? {
        var lone: Int?
        for index in stride(
            from: buffers.count - 1,
            through: 0,
            by: -1
        ) where buffers[index].mNumberChannels > 0 {
            if Int(buffers[index].mNumberChannels) == tapChannels {
                return buffers[index].mData == nil ? nil : index
            }
            if buffers.count == 1, buffers[index].mData != nil {
                lone = index
            }
        }
        return lone
    }

    private static func silence(
        _ buffers: UnsafeMutableAudioBufferListPointer
    ) {
        for buffer in buffers {
            if let data = buffer.mData {
                memset(data, 0, Int(buffer.mDataByteSize))
            }
        }
    }
}

private final class AtomicFloat: @unchecked Sendable {
    private var raw: Int32

    init(_ value: Float) {
        raw = Int32(bitPattern: value.bitPattern)
    }

    var value: Float {
        get {
            Float(
                bitPattern: UInt32(
                    bitPattern: OSAtomicAdd32Barrier(0, &raw)
                )
            )
        }
        set {
            let bits = Int32(bitPattern: newValue.bitPattern)
            while true {
                let current = raw
                if OSAtomicCompareAndSwap32Barrier(current, bits, &raw) {
                    break
                }
            }
        }
    }
}
