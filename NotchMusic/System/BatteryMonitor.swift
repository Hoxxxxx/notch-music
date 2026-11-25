import Foundation
import IOKit.ps

enum BatteryHUDSettings {
    static let showsBatteryInNotch =
        "NotchMusic.battery.showsBatteryInNotch"
    static let chargingHUDEnabled =
        "NotchMusic.battery.chargingHUDEnabled"
    static let lowBatteryHUDEnabled =
        "NotchMusic.battery.lowBatteryHUDEnabled"
    static let fullBatteryHUDEnabled =
        "NotchMusic.battery.fullBatteryHUDEnabled"
    static let lowBatteryThreshold =
        "NotchMusic.battery.lowBatteryThreshold"
    static let fullBatteryThreshold =
        "NotchMusic.battery.fullBatteryThreshold"
    static let hudDuration = "NotchMusic.battery.hudDuration"

    static func isEnabled(
        _ key: String,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard defaults.object(forKey: key) != nil else {
            return true
        }
        return defaults.bool(forKey: key)
    }

    static func threshold(
        _ key: String,
        fallback: Int,
        defaults: UserDefaults = .standard
    ) -> Int {
        guard defaults.object(forKey: key) != nil else {
            return fallback
        }
        return defaults.integer(forKey: key)
    }

    static func duration(defaults: UserDefaults = .standard) -> TimeInterval {
        guard defaults.object(forKey: hudDuration) != nil else {
            return 3
        }
        return TimeInterval(
            min(max(defaults.integer(forKey: hudDuration), 1), 10)
        )
    }
}

struct BatteryReading: Equatable {
    let level: Int
    let isCharging: Bool
    let isPluggedIn: Bool
    let isFullyCharged: Bool
    let isInLowPowerMode: Bool
    let timeToFullCharge: Int?
}

enum BatteryHUDKind: String, Equatable, Identifiable {
    case charging
    case lowBattery
    case fullBattery

    var id: String { rawValue }
}

struct BatteryHUDPresentation: Equatable, Identifiable {
    let id = UUID()
    let kind: BatteryHUDKind
    let level: Int
    let isCharging: Bool
    let isPluggedIn: Bool
    let isFullyCharged: Bool
    let isInLowPowerMode: Bool
    let timeToFullCharge: Int?
}

@MainActor
final class BatteryMonitor: ObservableObject {
    @Published private(set) var status: BatteryReading?
    @Published private(set) var presentation: BatteryHUDPresentation?
    @Published private(set) var hasBattery = false

    private var powerSource: CFRunLoopSource?
    private var lowPowerObserver: NSObjectProtocol?
    private var hideTask: Task<Void, Never>?
    private var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true

        refresh(triggersNotifications: false)
        observePowerSourceChanges()

        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(triggersNotifications: false)
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        hideTask?.cancel()
        hideTask = nil
        presentation = nil

        if let powerSource {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                powerSource,
                .defaultMode
            )
            self.powerSource = nil
        }

        if let lowPowerObserver {
            NotificationCenter.default.removeObserver(lowPowerObserver)
            self.lowPowerObserver = nil
        }
    }

    func refresh() {
        refresh(triggersNotifications: false)
    }

    func showTestHUD(_ kind: BatteryHUDKind) {
        guard let status else { return }

        let level: Int
        switch kind {
        case .charging:
            level = max(12, min(status.level, 95))
        case .lowBattery:
            level = min(
                max(
                    BatteryHUDSettings.threshold(
                        BatteryHUDSettings.lowBatteryThreshold,
                        fallback: 20
                    ),
                    5
                ),
                30
            )
        case .fullBattery:
            level = 100
        }

        presentHUD(
            kind: kind,
            levelOverride: level,
            force: true,
            isChargingOverride: kind == .charging,
            isPluggedInOverride: kind != .lowBattery,
            isFullyChargedOverride: kind == .fullBattery
        )
    }

    private func observePowerSourceChanges() {
        guard powerSource == nil,
              let source = IOPSNotificationCreateRunLoopSource(
                { context in
                    guard let context else { return }
                    let monitor = Unmanaged<BatteryMonitor>
                        .fromOpaque(context)
                        .takeUnretainedValue()
                    Task { @MainActor in
                        monitor.refresh(triggersNotifications: true)
                    }
                },
                Unmanaged.passUnretained(self).toOpaque()
              )?.takeRetainedValue() else {
            return
        }

        powerSource = source
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            source,
            .defaultMode
        )
    }

    private func refresh(triggersNotifications: Bool) {
        let previous = status
        let next = Self.readBattery()

        hasBattery = next != nil
        status = next

        guard triggersNotifications,
              let previous,
              let next,
              previous != next else {
            return
        }

        if !previous.isPluggedIn, next.isPluggedIn {
            presentHUD(kind: .charging)
        }

        let lowThreshold = BatteryHUDSettings.threshold(
            BatteryHUDSettings.lowBatteryThreshold,
            fallback: 20
        )
        if !next.isPluggedIn,
           previous.level > lowThreshold,
           next.level <= lowThreshold {
            presentHUD(kind: .lowBattery)
        }

        let fullThreshold = BatteryHUDSettings.threshold(
            BatteryHUDSettings.fullBatteryThreshold,
            fallback: 100
        )
        if previous.level < fullThreshold,
           next.level >= fullThreshold {
            presentHUD(kind: .fullBattery)
        }
    }

    private func presentHUD(
        kind: BatteryHUDKind,
        levelOverride: Int? = nil,
        force: Bool = false,
        isChargingOverride: Bool? = nil,
        isPluggedInOverride: Bool? = nil,
        isFullyChargedOverride: Bool? = nil
    ) {
        guard let status else { return }
        guard force || isHUDEnabled(for: kind) else { return }

        presentation = BatteryHUDPresentation(
            kind: kind,
            level: levelOverride ?? status.level,
            isCharging: isChargingOverride ?? status.isCharging,
            isPluggedIn: isPluggedInOverride ?? status.isPluggedIn,
            isFullyCharged: isFullyChargedOverride
                ?? status.isFullyCharged,
            isInLowPowerMode: status.isInLowPowerMode,
            timeToFullCharge: status.timeToFullCharge
        )

        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            let duration = BatteryHUDSettings.duration()
            try? await Task.sleep(
                nanoseconds: UInt64(duration * 1_000_000_000)
            )
            guard !Task.isCancelled else { return }
            self?.presentation = nil
        }
    }

    private func isHUDEnabled(for kind: BatteryHUDKind) -> Bool {
        switch kind {
        case .charging:
            return BatteryHUDSettings.isEnabled(
                BatteryHUDSettings.chargingHUDEnabled
            )
        case .lowBattery:
            return BatteryHUDSettings.isEnabled(
                BatteryHUDSettings.lowBatteryHUDEnabled
            )
        case .fullBattery:
            return BatteryHUDSettings.isEnabled(
                BatteryHUDSettings.fullBatteryHUDEnabled
            )
        }
    }

    private static func readBattery() -> BatteryReading? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?
                .takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?
                .takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(
                snapshot,
                source
            )?.takeUnretainedValue() as? [String: Any],
            let level = integer(
                description[kIOPSCurrentCapacityKey as String]
            ),
            let maxCapacity = integer(
                description[kIOPSMaxCapacityKey as String]
            ),
            maxCapacity > 0 else {
                continue
            }

            let powerSource = description[
                kIOPSPowerSourceStateKey as String
            ] as? String
            let isPluggedIn = powerSource == kIOPSACPowerValue
            let isCharging = description[
                kIOPSIsChargingKey as String
            ] as? Bool ?? false
            let isFullyCharged = description[
                kIOPSIsChargedKey as String
            ] as? Bool ?? false
            let timeToFullCharge = integer(
                description[kIOPSTimeToFullChargeKey as String]
            ).flatMap { value in
                value > 0 && value < 1_440 ? value : nil
            }

            return BatteryReading(
                level: min(max(Int((Double(level) / Double(maxCapacity) * 100).rounded()), 0), 100),
                isCharging: isCharging,
                isPluggedIn: isPluggedIn,
                isFullyCharged: isFullyCharged || level >= maxCapacity,
                isInLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                timeToFullCharge: timeToFullCharge
            )
        }

        return nil
    }

    private static func integer(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue ?? value as? Int
    }
}
