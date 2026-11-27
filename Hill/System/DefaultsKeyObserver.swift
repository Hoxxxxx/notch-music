import Combine
import Foundation

@MainActor
final class DefaultsKeyObserver {
    private let keys: [String]
    private let onChange: @MainActor () -> Void
    private var lastValues: NSDictionary
    private var cancellable: AnyCancellable?

    init(
        keys: [String],
        onChange: @escaping @MainActor () -> Void
    ) {
        self.keys = keys
        self.onChange = onChange
        lastValues = Self.snapshot(keys)

        cancellable = NotificationCenter.default.publisher(
            for: UserDefaults.didChangeNotification
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            Task { @MainActor in
                self?.check()
            }
        }
    }

    private func check() {
        let values = Self.snapshot(keys)
        guard !values.isEqual(lastValues) else { return }
        lastValues = values
        onChange()
    }

    private static func snapshot(_ keys: [String]) -> NSDictionary {
        var values: [String: Any] = [:]
        for key in keys {
            values[key] = UserDefaults.standard.object(forKey: key)
                ?? NSNull()
        }
        return values as NSDictionary
    }
}
