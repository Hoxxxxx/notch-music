import AppKit

struct NotchMetrics {
    let screen: NSScreen
    let notchWidth: CGFloat
    let topInset: CGFloat
    let notchLeading: CGFloat
    let notchTrailing: CGFloat
    let screenCenterX: CGFloat
}

enum NotchLayout {
    static let expandedHeight: CGFloat = 186
    static let expandedTopPadding: CGFloat = 42
    static let expandedBottomPadding: CGFloat = 12
    static let expandedHorizontalPadding: CGFloat = 35
    static let expandedColumnSpacing: CGFloat = 16
    static let expandedTopCornerRadius: CGFloat = 19
    static let physicalNotchOutline = "NotchMusic.physicalNotchOutline"
    static let alwaysExpanded = "NotchMusic.alwaysExpanded"
    static let expandedContentHeight =
        expandedHeight - expandedTopPadding - expandedBottomPadding

    private static let windowSideMargin: CGFloat = 60
    private static let windowBottomMargin: CGFloat = 60

    static func compactWidth(
        notchWidth: CGFloat,
        wingWidth: CGFloat
    ) -> CGFloat {
        notchWidth + max(wingWidth, 0) * 2
    }

    static func expandedWidth(notchWidth: CGFloat) -> CGFloat {
        max(500, notchWidth + 310)
    }

    static func sideHUDWidth(notchWidth: CGFloat) -> CGFloat {
        max(424, notchWidth + 228)
    }

    static func windowSize(for contentSize: CGSize) -> CGSize {
        CGSize(
            width: contentSize.width + windowSideMargin * 2,
            height: contentSize.height + windowBottomMargin
        )
    }
}

enum NotchGeometry {
    static func metrics(for screen: NSScreen) -> NotchMetrics? {
        let topInset = screen.safeAreaInsets.top
        guard topInset > 0 else { return nil }

        var width: CGFloat = 190
        let left = screen.auxiliaryTopLeftArea
        let right = screen.auxiliaryTopRightArea

        if let left, let right,
           left.width > 0,
           right.width > 0,
           right.minX > left.maxX {
            width = right.minX - left.maxX
        }

        return NotchMetrics(
            screen: screen,
            notchWidth: width,
            topInset: topInset,
            notchLeading: left?.maxX ?? 0,
            notchTrailing: right?.minX ?? 0,
            screenCenterX: screen.frame.midX
        )
    }

    static func activeScreen() -> NSScreen? {
        if let main = NSScreen.main, metrics(for: main) != nil {
            return main
        }
        return NSScreen.screens.first { metrics(for: $0) != nil }
    }
}
