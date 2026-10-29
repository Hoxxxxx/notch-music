import AppKit

struct NotchMetrics {
    let screen: NSScreen
    let notchWidth: CGFloat
    let topInset: CGFloat
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
            width = right.minX - left.maxX
        }

        return NotchMetrics(
            screen: screen,
            notchWidth: max(width, 160),
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
