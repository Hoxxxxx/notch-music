import Combine
import Foundation

@MainActor
final class NotchPanelState: ObservableObject {
    @Published private(set) var isExpanded = false

    private var isHovering = false
    private var collapseTask: Task<Void, Never>?

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
        if hovering {
            collapseTask?.cancel()
            isExpanded = true
        } else {
            scheduleCollapse(after: 0.18)
        }
    }

    func expandTemporarily(for seconds: TimeInterval = 6) {
        isExpanded = true
        scheduleCollapse(after: seconds)
    }

    private func scheduleCollapse(after seconds: TimeInterval) {
        collapseTask?.cancel()
        guard !isHovering else { return }

        collapseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.isExpanded = false
        }
    }
}
