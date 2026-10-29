import Combine
import Foundation

@MainActor
final class NotchPanelState: ObservableObject {
    @Published private(set) var isExpanded = false
    @Published private(set) var notchWidth: CGFloat = 190
    @Published private(set) var topInset: CGFloat = 32

    private var isHovering = false
    private var hoverTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?

    func updateMetrics(notchWidth: CGFloat, topInset: CGFloat) {
        self.notchWidth = notchWidth
        self.topInset = topInset
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
        hoverTask?.cancel()

        if hovering {
            collapseTask?.cancel()
            guard !isExpanded else { return }

            hoverTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 160_000_000)
                guard !Task.isCancelled else { return }
                self?.isExpanded = true
            }
        } else {
            scheduleCollapse(after: 0.16)
        }
    }

    func expand() {
        hoverTask?.cancel()
        collapseTask?.cancel()
        isExpanded = true
    }

    func expandTemporarily(for seconds: TimeInterval = 6) {
        hoverTask?.cancel()
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
