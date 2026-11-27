import AppKit
import ApplicationServices
import Carbon
import EventKit
import SwiftUI

enum OnboardingSettings {
    static let completedKey = "NotchMusic.didCompleteOnboarding"

    static var isCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: completedKey)
    }
}

enum MusicAutomationState: Equatable {
    case granted
    case denied
    case notDetermined

    static var current: MusicAutomationState {
        var address = AEAddressDesc()
        let bundleID = Data("com.apple.Music".utf8)
        let created = bundleID.withUnsafeBytes { buffer in
            AECreateDesc(
                DescType(typeApplicationBundleID),
                buffer.baseAddress,
                bundleID.count,
                &address
            )
        }
        guard created == noErr else {
            return .notDetermined
        }
        defer { AEDisposeDesc(&address) }

        let status = AEDeterminePermissionToAutomateTarget(
            &address,
            AEEventClass(typeWildCard),
            AEEventID(typeWildCard),
            false
        )
        switch status {
        case noErr:
            return .granted
        case -1743, -1744:
            return .denied
        default:
            return .notDetermined
        }
    }
}

@MainActor
final class OnboardingModel: ObservableObject {
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var musicAutomation: MusicAutomationState = .notDetermined
    @Published private(set) var calendarStatus: EKAuthorizationStatus = .notDetermined

    private let eventStore = EKEventStore()

    func refresh() {
        let granted = AXIsProcessTrusted()
        if accessibilityGranted != granted {
            accessibilityGranted = granted
        }

        let automation = MusicAutomationState.current
        if musicAutomation != automation {
            musicAutomation = automation
        }

        let calendar = EKEventStore.authorizationStatus(for: .event)
        if calendarStatus != calendar {
            calendarStatus = calendar
        }
    }

    func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions(
            ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.openAccessibilitySettings()
        }
    }

    func requestMusicAutomation() {
        var error: NSDictionary?
        NSAppleScript(
            source: "tell application \"Music\" to get player state"
        )?.executeAndReturnError(&error)
        refresh()
    }

    func requestCalendar() {
        Task {
            _ = try? await eventStore.requestFullAccessToEvents()
            refresh()
        }
    }

    func openAccessibilitySettings() {
        open(
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        )
    }

    func openAutomationSettings() {
        open(
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        )
    }

    func openCalendarSettings() {
        open(
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        )
    }

    private func open(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }
}

struct OnboardingView: View {
    let onFinish: () -> Void

    @StateObject private var model = OnboardingModel()
    @State private var isPointerInside = false

    private let refreshTimer = Timer.publish(
        every: 1,
        on: .main,
        in: .common
    ).autoconnect()

    var body: some View {
        ZStack {
            SettingsBackdrop()

            VStack(spacing: 18) {
                header
                featureRow

                PermissionCards(model: model)

                Spacer(minLength: 0)

                Text("音频频谱会在首次播放时由系统单独请求音频录制权限。")
                    .settingsCaption()
                    .frame(maxWidth: .infinity, alignment: .leading)

                footer
            }
            .padding(24)
        }
        .frame(width: 540, height: 600)
        .environment(\.settingsPreviewsActive, isPointerInside)
        .onHover { hovering in
            isPointerInside = hovering
        }
        .onAppear {
            model.refresh()
        }
        .onReceive(refreshTimer) { _ in
            model.refresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            model.refresh()
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 76, height: 76)
                .clipShape(
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                )
                .shadow(color: .black.opacity(0.2), radius: 14, y: 7)

            Text("欢迎使用 Hill")
                .font(.system(size: 23, weight: .bold))

            Text("把音乐、系统状态和鼠标手势收进刘海。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 6)
    }

    private var featureRow: some View {
        HStack(spacing: 6) {
            featurePill("music.note", "音乐控制", tint: .pink)
            featurePill("waveform", "系统 HUD", tint: .orange)
            featurePill("computermouse.fill", "鼠标平滑", tint: .teal)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("权限可随时在系统设置中修改")
                .settingsCaption()

            Spacer()

            Button("稍后设置") {
                onFinish()
            }
            .controlSize(.large)

            Button("开始使用") {
                onFinish()
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func featurePill(
        _ icon: String,
        _ title: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(title)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(tint.opacity(0.13), in: Capsule())
    }

}

struct PermissionsSettingsView: View {
    @StateObject private var model = OnboardingModel()

    private let refreshTimer = Timer.publish(
        every: 1,
        on: .main,
        in: .common
    ).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Label("授权", systemImage: "lock.shield.fill")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Text("\(grantedCount) / 3 已授权")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(grantedCount == 3 ? .green : .secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        (grantedCount == 3 ? Color.green : Color.secondary)
                            .opacity(0.12),
                        in: Capsule()
                    )
            }

            Text("Hill 只在本机使用这些权限，可随时在系统设置中修改。")
                .settingsCaption()

            Divider()
                .opacity(0.5)

            PermissionCards(model: model, presentation: .settingsRow)

            Divider()
                .opacity(0.5)

            HStack(spacing: 6) {
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)

                Text("实时频谱会在首次播放时单独请求音频录制权限。")
                    .settingsCaption()
            }

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "cloud.sun.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)

                Text("天气取自“天气/Weather”日历中含温度的全天事件，如标题“18° 晴”。")
                    .settingsCaption()
            }
        }
        .onAppear {
            model.refresh()
        }
        .onReceive(refreshTimer) { _ in
            model.refresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            model.refresh()
        }
    }

    private var grantedCount: Int {
        (model.accessibilityGranted ? 1 : 0)
            + (model.musicAutomation == .granted ? 1 : 0)
            + (model.calendarStatus == .fullAccess ? 1 : 0)
    }
}

private enum PermissionCardPresentation: Equatable {
    case standalone
    case settingsRow
}

private struct PermissionCards: View {
    @ObservedObject var model: OnboardingModel
    var presentation: PermissionCardPresentation = .standalone

    var body: some View {
        if presentation == .settingsRow {
            VStack(spacing: 0) {
                accessibilityCard
                rowDivider
                musicCard
                rowDivider
                calendarCard
            }
        } else {
            VStack(spacing: 10) {
                accessibilityCard
                musicCard
                calendarCard
            }
        }
    }

    private var rowDivider: some View {
        Divider()
            .opacity(0.35)
    }

    private var accessibilityCard: some View {
        let granted = model.accessibilityGranted
        return PermissionCard(
            presentation: presentation,
            icon: "hand.raised.fill",
            tint: .blue,
            title: "辅助功能",
            badge: "必需",
            detail: "用于鼠标平滑与滚动翻转，以及音量、亮度媒体键 HUD。",
            status: granted
                ? "已授权"
                : presentation == .settingsRow
                    ? "未授权"
                    : "未授权，请在系统设置中开启",
            statusColor: granted ? .green : .orange,
            actionTitle: granted ? "系统设置" : "授权"
        ) {
            if granted {
                model.openAccessibilitySettings()
            } else {
                model.requestAccessibility()
            }
        }
    }

    private var musicCard: some View {
        PermissionCard(
            presentation: presentation,
            icon: "music.note",
            tint: .pink,
            title: "音乐控制",
            badge: "推荐",
            detail: "读取并控制 Apple Music；授权时会自动打开音乐 App。",
            status: musicStatus.text,
            statusColor: musicStatus.color,
            actionTitle: model.musicAutomation == .notDetermined
                ? "授权"
                : "系统设置"
        ) {
            if model.musicAutomation == .notDetermined {
                model.requestMusicAutomation()
            } else {
                model.openAutomationSettings()
            }
        }
    }

    private var calendarCard: some View {
        PermissionCard(
            presentation: presentation,
            icon: "calendar",
            tint: .green,
            title: "日历",
            badge: "可选",
            detail: "在刘海日历中显示当天日程，日程只在本机读取。",
            status: calendarStatusText.text,
            statusColor: calendarStatusText.color,
            actionTitle: model.calendarStatus == .notDetermined
                ? "授权"
                : "系统设置"
        ) {
            if model.calendarStatus == .notDetermined {
                model.requestCalendar()
            } else {
                model.openCalendarSettings()
            }
        }
    }

    private var musicStatus: (text: String, color: Color) {
        switch model.musicAutomation {
        case .granted:
            return ("已授权", .green)
        case .denied:
            return (
                presentation == .settingsRow
                    ? "已拒绝"
                    : "已被拒绝，请在系统设置中开启",
                .orange
            )
        case .notDetermined:
            return ("未授权", .secondary)
        }
    }

    private var calendarStatusText: (text: String, color: Color) {
        switch model.calendarStatus {
        case .fullAccess:
            return ("已授权", .green)
        case .denied, .restricted, .writeOnly:
            return (
                presentation == .settingsRow
                    ? "已拒绝"
                    : "已被拒绝，请在系统设置中开启",
                .orange
            )
        case .notDetermined:
            return ("未授权", .secondary)
        @unknown default:
            return ("状态未知", .secondary)
        }
    }
}

private struct PermissionCard: View {
    let presentation: PermissionCardPresentation
    let icon: String
    let tint: Color
    let title: String
    let badge: String
    let detail: String
    let status: String
    let statusColor: Color
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        if presentation == .settingsRow {
            rowContent
                .padding(.vertical, 12)
        } else {
            rowContent
                .padding(13)
                .settingsGlassSurface(cornerRadius: 16)
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(
                    tint.opacity(0.16),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))

                    Text(badge)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(tint.opacity(0.16), in: Capsule())

                    if presentation == .settingsRow {
                        Text(status)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(statusColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                statusColor.opacity(0.14),
                                in: Capsule()
                            )
                    }

                    Spacer(minLength: 0)
                }

                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if presentation == .standalone {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 5, height: 5)
                        Text(status)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if presentation == .settingsRow, actionTitle == "授权" {
                Button(actionTitle, action: action)
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            } else {
                Button(actionTitle, action: action)
                    .controlSize(.small)
                    .buttonStyle(.bordered)
            }
        }
    }
}
