import Combine
import CoreAudio
import Foundation

struct DeviceConnectionPresentation: Equatable {
    let deviceName: String
    let model: AirPodsModelKind
    let volume: Double?
    let isMuted: Bool
}

@MainActor
final class DeviceConnectionMonitor: ObservableObject {
    private static let keepsAirPodsPresentationVisible = false

    @Published private(set) var presentation: DeviceConnectionPresentation?

    private let controlBackend = SystemControlBackend()
    private var defaultOutputListener: AudioObjectPropertyListenerBlock?
    private var lastOutputIdentifier: String?
    private var classificationTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var volumeRefreshTask: Task<Void, Never>?
    private var selectionCancellable: AnyCancellable?
    private var detectedModel = AirPodsModelKind.airPodsPro
    private var isStarted = false

    func start() {
        guard !isStarted else { return }
        isStarted = true
        let output = Self.defaultOutputDevice()
        lastOutputIdentifier = output?.identifier
        if Self.keepsAirPodsPresentationVisible,
           let output,
           output.isAirPods {
            presentConnectedAirPods(output)
        }

        var address = Self.defaultOutputAddress
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.defaultOutputDidChange()
            }
        }
        guard AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            listener
        ) == noErr else {
            isStarted = false
            return
        }
        defaultOutputListener = listener

        selectionCancellable = NotificationCenter.default.publisher(
            for: UserDefaults.didChangeNotification
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            Task { @MainActor in
                self?.preferredModelDidChange()
            }
        }
    }

    func stop() {
        hideTask?.cancel()
        hideTask = nil
        classificationTask?.cancel()
        classificationTask = nil
        selectionCancellable?.cancel()
        selectionCancellable = nil
        volumeRefreshTask?.cancel()
        volumeRefreshTask = nil
        presentation = nil

        if let defaultOutputListener {
            var address = Self.defaultOutputAddress
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                defaultOutputListener
            )
        }
        defaultOutputListener = nil
        lastOutputIdentifier = nil
        isStarted = false
    }

    private func defaultOutputDidChange() {
        let output = Self.defaultOutputDevice()
        guard output?.identifier != lastOutputIdentifier else { return }
        lastOutputIdentifier = output?.identifier

        guard let output, output.isAirPods else {
            dismiss()
            return
        }
        presentConnectedAirPods(output)
    }

    private func presentConnectedAirPods(_ output: AudioOutputDevice) {
        classificationTask?.cancel()
        hideTask?.cancel()
        hideTask = nil
        volumeRefreshTask?.cancel()
        volumeRefreshTask = nil

        classificationTask = Task { [weak self] in
            let model = await Self.airPodsModel(for: output)
            guard !Task.isCancelled, let self else { return }
            guard let current = Self.defaultOutputDevice(),
                  current.identifier == output.identifier else {
                return
            }
            self.showConnectedAirPods(output, model: model)
        }
    }

    private func showConnectedAirPods(
        _ output: AudioOutputDevice,
        model: AirPodsModelKind
    ) {
        detectedModel = model
        presentation = DeviceConnectionPresentation(
            deviceName: output.name,
            model: effectiveModel(detected: model),
            volume: currentVolume,
            isMuted: currentIsMuted
        )

        volumeRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled, let self else { return }
                guard let output = Self.defaultOutputDevice(),
                      output.isAirPods else {
                    self.dismiss()
                    return
                }
                self.updateVolume()
            }
        }

        if !Self.keepsAirPodsPresentationVisible {
            hideTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                self?.dismiss()
            }
        }
    }

    private var currentVolume: Double? {
        controlBackend.currentState(.volume)?.level
    }

    private var currentIsMuted: Bool {
        controlBackend.currentState(.volume)?.isMuted ?? false
    }

    private func updateVolume() {
        guard let presentation else { return }
        let next = DeviceConnectionPresentation(
            deviceName: presentation.deviceName,
            model: presentation.model,
            volume: currentVolume,
            isMuted: currentIsMuted
        )
        guard next != presentation else { return }
        self.presentation = next
    }

    private func preferredModelDidChange() {
        guard let presentation else { return }
        let model = effectiveModel(detected: detectedModel)
        guard model != presentation.model else { return }
        self.presentation = DeviceConnectionPresentation(
            deviceName: presentation.deviceName,
            model: model,
            volume: presentation.volume,
            isMuted: presentation.isMuted
        )
    }

    private func effectiveModel(
        detected: AirPodsModelKind
    ) -> AirPodsModelKind {
        let rawValue = UserDefaults.standard.string(
            forKey: AirPodsModelSelection.storageKey
        )
        let selection = rawValue.flatMap(
            AirPodsModelSelection.init(rawValue:)
        ) ?? .automatic
        return selection.model ?? detected
    }

    private func dismiss() {
        classificationTask?.cancel()
        classificationTask = nil
        hideTask?.cancel()
        hideTask = nil
        volumeRefreshTask?.cancel()
        volumeRefreshTask = nil
        presentation = nil
    }

    private nonisolated static func airPodsModel(
        for output: AudioOutputDevice
    ) async -> AirPodsModelKind {
        let productID = await bluetoothProductID(for: output.uid)
        return AirPodsModelKind.inferred(
            from: output.name,
            productID: productID
        )
    }

    private nonisolated static func bluetoothProductID(
        for deviceUID: String?
    ) async -> UInt16? {
        await Task.detached(priority: .utility) {
            guard let deviceUID,
                  let targetAddress = normalizedDeviceAddress(deviceUID)
            else {
                return nil
            }

            let process = Process()
            process.executableURL = URL(
                fileURLWithPath: "/usr/sbin/system_profiler"
            )
            process.arguments = ["SPBluetoothDataType", "-json"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                return nil
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let json = try? JSONSerialization.jsonObject(with: data)
                    as? [String: Any],
                  let sections = json["SPBluetoothDataType"]
                    as? [[String: Any]] else {
                return nil
            }

            for section in sections {
                guard let devices = section["device_connected"]
                    as? [[String: Any]] else {
                    continue
                }
                for entry in devices {
                    for value in entry.values {
                        guard let details = value as? [String: Any],
                              let address = details["device_address"]
                                as? String,
                              normalizedDeviceAddress(address)
                                == targetAddress,
                              let rawProductID = details["device_productID"]
                                as? String else {
                            continue
                        }
                        return UInt16(
                            rawProductID
                                .replacingOccurrences(
                                    of: "0x",
                                    with: "",
                                    options: .caseInsensitive
                                ),
                            radix: 16
                        )
                    }
                }
            }
            return nil
        }.value
    }

    private nonisolated static func normalizedDeviceAddress(
        _ value: String
    ) -> String? {
        let address = value.hasSuffix(":output")
            ? String(value.dropLast(":output".count))
            : value
        let normalized = address
            .filter(\.isHexDigit)
            .uppercased()
        return normalized.isEmpty ? nil : normalized
    }

    private static var defaultOutputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func defaultOutputDevice() -> AudioOutputDevice? {
        var address = defaultOutputAddress
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

        let uid = stringProperty(
            deviceID: deviceID,
            selector: kAudioDevicePropertyDeviceUID
        )
        let name = stringProperty(
            deviceID: deviceID,
            selector: kAudioObjectPropertyName
        ) ?? "AirPods"
        let manufacturer = stringProperty(
            deviceID: deviceID,
            selector: kAudioObjectPropertyManufacturer
        )
        let transportType = uint32Property(
            deviceID: deviceID,
            selector: kAudioDevicePropertyTransportType
        )

        return AudioOutputDevice(
            id: deviceID,
            uid: uid,
            name: name,
            manufacturer: manufacturer,
            transportType: transportType
        )
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

private struct AudioOutputDevice {
    let id: AudioDeviceID
    let uid: String?
    let name: String
    let manufacturer: String?
    let transportType: UInt32?

    var identifier: String {
        uid ?? String(id)
    }

    var isAirPods: Bool {
        name.localizedCaseInsensitiveContains("AirPods")
            || uid?.localizedCaseInsensitiveContains("AirPods") == true
            || (
                transportType == kAudioDeviceTransportTypeBluetooth
                    && manufacturer?.localizedCaseInsensitiveContains(
                        "Apple"
                    ) == true
            )
    }
}
