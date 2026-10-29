import AppKit

struct NotchMetrics {
    let screen: NSScreen
    let notchWidth: CGFloat
    let topInset: CGFloat
}

enum NotchLayout {
    static let expandedHeight: CGFloat = 188

    private static let windowWidthMargin: CGFloat = 32
    private static let windowHeightMargin: CGFloat = 24

    static func compactWidth(notchWidth: CGFloat, isPlaying: Bool) -> CGFloat {
        isPlaying ? notchWidth + 56 : notchWidth
    }

    static func expandedWidth(notchWidth: CGFloat) -> CGFloat {
        max(340, notchWidth + 150)
    }

    static func windowSize(notchWidth: CGFloat) -> CGSize {
        CGSize(
            width: expandedWidth(notchWidth: notchWidth) + windowWidthMargin,
            height: expandedHeight + windowHeightMargin
        )
    }
}

enum NotchGeometry {
    static func metrics(for screen: NSScreen) -> NotchMetrics? {
        let topInset = screen.safeAreaInsets.top
        guard topInset > 0 else { return nil }

        var width: CGFloat = 190
        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea,
           left.width > 0,
           right.width > 0,
           right.minX > left.maxX {
            width = right.minX - left.maxX + 4
        }

        return NotchMetrics(
            screen: screen,
            notchWidth: width,
            topInset: topInset
        )
    }

    static func activeScreen() -> NSScreen? {
        if let main = NSScreen.main, metrics(for: main) != nil {
            return main
        }
        return NSScreen.screens.first { metrics(for: $0) != nil }
    }
}
