import AppKit
import Darwin
import os

/// Moves the existing notch panel into the lock-screen SkyLight space.
///
/// Reusing the same window avoids a visual handoff between two panels when the
/// screen unlocks. The private-API technique is based on the MIT-licensed
/// Lakr233/SkyLightWindow project.
@MainActor
final class LockScreenIslandController {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "NotchMusic",
        category: "LockScreen"
    )
    private var delegatedWindowNumber = 0

    @discardableResult
    func enter(panel: NSPanel) -> Bool {
        panel.level = NSWindow.Level(
            rawValue: Int(CGShieldingWindowLevel())
        )
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        guard let skyLightSpace = LockScreenSkyLightSpace.shared,
              skyLightSpace.delegate(panel) else {
            logger.error("Unable to place notch panel in SkyLight space")
            panel.level = .statusBar
            panel.ignoresMouseEvents = false
            return false
        }

        delegatedWindowNumber = panel.windowNumber
        logger.info(
            "Notch panel on lock screen: window=\(panel.windowNumber)"
        )
        return true
    }

    func leave(panel: NSPanel) {
        if delegatedWindowNumber != 0 {
            LockScreenSkyLightSpace.shared?.undelegate(
                windowNumber: delegatedWindowNumber
            )
            delegatedWindowNumber = 0
        }
        panel.level = .statusBar
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
        logger.info(
            "Notch panel restored: window=\(panel.windowNumber)"
        )
    }
}

@MainActor
private final class LockScreenSkyLightSpace {
    static let shared = LockScreenSkyLightSpace()

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetAbsoluteLevel =
        @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Void
    private typealias SpaceAddWindows =
        @convention(c) (Int32, Int32, CFArray, Int32) -> Void
    private typealias SpaceRemoveWindows =
        @convention(c) (Int32, CFArray, CFArray) -> Int32

    /// kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock.
    private static let lockScreenLevel: Int32 = 400

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "NotchMusic",
        category: "LockScreen"
    )
    private let mainConnectionID: MainConnectionID
    private let createSpace: SpaceCreate
    private let setAbsoluteLevel: SpaceSetAbsoluteLevel
    private let showSpaces: ShowSpaces
    private let addWindows: SpaceAddWindows
    private let removeWindows: SpaceRemoveWindows

    private var connection: Int32 = 0
    private var space: Int32 = 0

    private init?() {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
            RTLD_NOW
        ) ?? dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            RTLD_NOW
        ) else {
            return nil
        }

        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let value = dlsym(handle, name) else { return nil }
            return unsafeBitCast(value, to: T.self)
        }

        guard let mainConnectionID = symbol(
            "SLSMainConnectionID",
            as: MainConnectionID.self
        ),
        let createSpace = symbol("SLSSpaceCreate", as: SpaceCreate.self),
        let setAbsoluteLevel = symbol(
            "SLSSpaceSetAbsoluteLevel",
            as: SpaceSetAbsoluteLevel.self
        ),
        let showSpaces = symbol("SLSShowSpaces", as: ShowSpaces.self),
        let addWindows = symbol(
            "SLSSpaceAddWindowsAndRemoveFromSpaces",
            as: SpaceAddWindows.self
        ),
        let removeWindows = symbol(
            "SLSRemoveWindowsFromSpaces",
            as: SpaceRemoveWindows.self
        ) else {
            return nil
        }

        self.mainConnectionID = mainConnectionID
        self.createSpace = createSpace
        self.setAbsoluteLevel = setAbsoluteLevel
        self.showSpaces = showSpaces
        self.addWindows = addWindows
        self.removeWindows = removeWindows
    }

    func delegate(_ window: NSWindow) -> Bool {
        guard ensureSpace(), window.windowNumber > 0 else {
            return false
        }

        addWindows(
            connection,
            space,
            [NSNumber(value: window.windowNumber)] as CFArray,
            7
        )
        return true
    }

    func undelegate(windowNumber: Int) {
        guard space != 0, windowNumber > 0 else { return }
        _ = removeWindows(
            connection,
            [NSNumber(value: windowNumber)] as CFArray,
            [NSNumber(value: space)] as CFArray
        )
    }

    private func ensureSpace() -> Bool {
        if space != 0 { return true }

        connection = mainConnectionID()
        guard connection != 0 else {
            logger.error("SLSMainConnectionID returned 0")
            return false
        }

        space = createSpace(connection, 1, 0)
        guard space != 0 else {
            logger.error("SLSSpaceCreate returned 0")
            return false
        }

        _ = setAbsoluteLevel(connection, space, Self.lockScreenLevel)
        showSpaces(connection, [NSNumber(value: space)] as CFArray)
        return true
    }
}
