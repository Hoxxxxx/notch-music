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
    static let compactExpandedHeight: CGFloat = 176
    static let expandedTopPadding: CGFloat = 42
    static let expandedBottomPadding: CGFloat = 12
    static let expandedHorizontalPadding: CGFloat = 35
    static let expandedColumnSpacing: CGFloat = 16
    static let expandedTopCornerRadius: CGFloat = 19
    static let physicalNotchOutline = "NotchMusic.physicalNotchOutline"
    static let alwaysExpanded = "NotchMusic.alwaysExpanded"
    static let notchWidthAdjustment = "NotchMusic.notchWidthAdjustment"
    static let notchHeightAdjustment = "NotchMusic.notchHeightAdjustment"
    static let notchWidthAdjustmentLimit = 40
    static let notchHeightAdjustmentLimit = 16
    static let notchPreviewWidth = "NotchMusic.notchPreviewWidth"
    static let notchPreviewHeight = "NotchMusic.notchPreviewHeight"
    static let notchPreviewActive = "NotchMusic.notchPreviewActive"
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
        var topInset = screen.safeAreaInsets.top
        guard topInset > 0 else { return nil }

        var width: CGFloat = 190
        var leading = screen.auxiliaryTopLeftArea?.maxX ?? 0
        var trailing = screen.auxiliaryTopRightArea?.minX ?? 0
        var usesDetectedEdges = false
        let left = screen.auxiliaryTopLeftArea
        let right = screen.auxiliaryTopRightArea

        if let left, let right,
           left.width > 0,
           right.width > 0,
           right.minX > left.maxX {
            width = right.minX - left.maxX
            usesDetectedEdges = true
        }

        let rawAdjustment = UserDefaults.standard.integer(
            forKey: NotchLayout.notchWidthAdjustment
        )
        let adjustment = CGFloat(
            min(
                max(rawAdjustment, -NotchLayout.notchWidthAdjustmentLimit),
                NotchLayout.notchWidthAdjustmentLimit
            )
        )
        if adjustment != 0 {
            width = max(width + adjustment, 120)
            if usesDetectedEdges {
                leading -= adjustment / 2
                trailing += adjustment / 2
            }
        }

        let rawHeightAdjustment = UserDefaults.standard.integer(
            forKey: NotchLayout.notchHeightAdjustment
        )
        let heightAdjustment = CGFloat(
            min(
                max(rawHeightAdjustment, -NotchLayout.notchHeightAdjustmentLimit),
                NotchLayout.notchHeightAdjustmentLimit
            )
        )
        if heightAdjustment != 0 {
            topInset = max(topInset + heightAdjustment, 12)
        }

        return NotchMetrics(
            screen: screen,
            notchWidth: width,
            topInset: topInset,
            notchLeading: leading,
            notchTrailing: trailing,
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
