import CoreAudio
import Foundation

struct DeviceConnectionPresentation: Equatable {
    let deviceName: String
    let model: AirPodsModelKind
    let batteryLevel: Double?
}

@MainActor
final class DeviceConnectionMonitor: ObservableObject {
    private static let keepsAirPodsPresentationVisible = false

    @Published private(set) var presentation: DeviceConnectionPresentation?

    private var defaultOutputListener: AudioObjectPropertyListenerBlock?
    private var lastOutputIdentifier: String?
    private var classificationTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
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
    }

    func stop() {
        hideTask?.cancel()
        hideTask = nil
        classificationTask?.cancel()
        classificationTask = nil
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

        classificationTask = Task { [weak self] in
            let info = await Self.airPodsConnectionInfo(for: output)
            guard !Task.isCancelled, let self else { return }
            guard let current = Self.defaultOutputDevice(),
                  current.identifier == output.identifier else {
                return
            }
            self.showConnectedAirPods(output, info: info)
        }
    }

    private func showConnectedAirPods(
        _ output: AudioOutputDevice,
        info: AirPodsConnectionInfo
    ) {
        let model = AirPodsModelKind.inferred(
            from: output.name,
            productID: info.productID
        )
        presentation = DeviceConnectionPresentation(
            deviceName: output.name,
            model: model,
            batteryLevel: info.batteryLevel
        )

        if !Self.keepsAirPodsPresentationVisible {
            hideTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                self?.dismiss()
            }
        }
    }

    private func dismiss() {
        classificationTask?.cancel()
        classificationTask = nil
        hideTask?.cancel()
        hideTask = nil
        presentation = nil
    }

    private nonisolated static func airPodsConnectionInfo(
        for output: AudioOutputDevice
    ) async -> AirPodsConnectionInfo {
        await bluetoothConnectionInfo(for: output.uid)
    }

    private nonisolated static func bluetoothConnectionInfo(
        for deviceUID: String?
    ) async -> AirPodsConnectionInfo {
        await Task.detached(priority: .utility) {
            guard let deviceUID,
                  let targetAddress = normalizedDeviceAddress(deviceUID)
            else {
                return AirPodsConnectionInfo()
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
                return AirPodsConnectionInfo()
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let json = try? JSONSerialization.jsonObject(with: data)
                    as? [String: Any],
                  let sections = json["SPBluetoothDataType"]
                    as? [[String: Any]] else {
                return AirPodsConnectionInfo()
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
                                == targetAddress else {
                            continue
                        }
                        let rawProductID = details["device_productID"]
                            as? String
                        return AirPodsConnectionInfo(
                            productID: rawProductID.flatMap {
                                UInt16(
                                    $0.replacingOccurrences(
                                        of: "0x",
                                        with: "",
                                        options: .caseInsensitive
                                    ),
                                    radix: 16
                                )
                            },
                            batteryLevel: batteryLevel(from: details)
                        )
                    }
                }
            }
            return AirPodsConnectionInfo()
        }.value
    }

    private nonisolated static func batteryLevel(
        from details: [String: Any]
    ) -> Double? {
        let primaryKeys = [
            "device_batteryLevel",
            "device_batteryLevelLeft",
            "device_batteryLevelRight"
        ]
        let primaryLevels = primaryKeys.compactMap {
            batteryPercentage(details[$0])
        }
        if let level = primaryLevels.min() {
            return level
        }
        return batteryPercentage(details["device_batteryLevelCase"])
    }

    private nonisolated static func batteryPercentage(
        _ rawValue: Any?
    ) -> Double? {
        let value: Double?
        if let number = rawValue as? NSNumber {
            value = number.doubleValue
        } else if let string = rawValue as? String {
            value = Double(
                string.filter { $0.isNumber || $0 == "." }
            )
        } else {
            value = nil
        }
        guard let value else { return nil }
        return min(max(value / 100, 0), 1)
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

private struct AirPodsConnectionInfo {
    let productID: UInt16?
    let batteryLevel: Double?

    init(
        productID: UInt16? = nil,
        batteryLevel: Double? = nil
    ) {
        self.productID = productID
        self.batteryLevel = batteryLevel
    }
}
