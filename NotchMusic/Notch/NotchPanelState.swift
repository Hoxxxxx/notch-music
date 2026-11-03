import Combine
import Foundation

@MainActor
final class NotchPanelState: ObservableObject {
    @Published private(set) var isExpanded = false
    @Published private(set) var isHoverPreviewActive = false
    @Published private(set) var notchWidth: CGFloat = 190
    @Published private(set) var topInset: CGFloat = 32
    @Published private(set) var notchLeading: CGFloat = 0
    @Published private(set) var notchTrailing: CGFloat = 0
    @Published private(set) var screenCenterX: CGFloat = 0

    private var isHovering = false
    private var isPinnedExpanded: Bool
    private var restoresExpandedAfterScreenLock = false
    private var hoverTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var settingsObserver: AnyCancellable?

    init() {
        isPinnedExpanded = UserDefaults.standard.bool(
            forKey: NotchLayout.alwaysExpanded
        )
        isExpanded = isPinnedExpanded
        settingsObserver = NotificationCenter.default.publisher(
            for: UserDefaults.didChangeNotification
        )
        .sink { [weak self] _ in
            Task { @MainActor in
                self?.refreshPinnedState()
            }
        }
    }

    func updateMetrics(
        notchWidth: CGFloat,
        topInset: CGFloat,
        notchLeading: CGFloat = 0,
        notchTrailing: CGFloat = 0,
        screenCenterX: CGFloat = 0
    ) {
        self.notchWidth = notchWidth
        self.topInset = topInset
        self.notchLeading = notchLeading
        self.notchTrailing = notchTrailing
        self.screenCenterX = screenCenterX
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
        hoverTask?.cancel()

        if isPinnedExpanded {
            collapseTask?.cancel()
            isHoverPreviewActive = false
            isExpanded = true
            return
        }

        if hovering {
            collapseTask?.cancel()
            guard !isExpanded else { return }

            isHoverPreviewActive = true
            hoverTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 360_000_000)
                guard !Task.isCancelled else { return }
                self?.isExpanded = true
            }
        } else {
            isHoverPreviewActive = false
            scheduleCollapse(after: 0.16)
        }
    }

    func expand() {
        hoverTask?.cancel()
        collapseTask?.cancel()
        isHoverPreviewActive = false
        isExpanded = true
    }

    func expandTemporarily(for seconds: TimeInterval = 6) {
        hoverTask?.cancel()
        isHoverPreviewActive = false
        isExpanded = true
        guard !isPinnedExpanded else { return }
        scheduleCollapse(after: seconds)
    }

    func collapseForScreenLock() {
        restoresExpandedAfterScreenLock = isPinnedExpanded
        hoverTask?.cancel()
        collapseTask?.cancel()
        isHovering = false
        isHoverPreviewActive = false
        isExpanded = false
    }

    func restoreAfterScreenLock() {
        guard restoresExpandedAfterScreenLock else { return }
        restoresExpandedAfterScreenLock = false
        isExpanded = true
    }

    private func scheduleCollapse(after seconds: TimeInterval) {
        collapseTask?.cancel()
        guard !isPinnedExpanded else {
            isExpanded = true
            return
        }
        guard !isHovering else { return }

        collapseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.isExpanded = false
        }
    }

    private func refreshPinnedState() {
        let pinned = UserDefaults.standard.bool(
            forKey: NotchLayout.alwaysExpanded
        )
        guard pinned != isPinnedExpanded else { return }

        isPinnedExpanded = pinned
        if pinned {
            hoverTask?.cancel()
            collapseTask?.cancel()
            isHoverPreviewActive = false
            isExpanded = true
        } else if !isHovering {
            scheduleCollapse(after: 0.16)
        }
    }
}
