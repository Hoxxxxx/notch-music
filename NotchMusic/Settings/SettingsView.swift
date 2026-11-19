import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct SettingsPreviewsActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var settingsPreviewsActive: Bool {
        get { self[SettingsPreviewsActiveKey.self] }
        set { self[SettingsPreviewsActiveKey.self] = newValue }
    }
}
enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case mouse
    case hud
    case music
    case watchFace
    case detection
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "通用"
        case .mouse:
            return "鼠标"
        case .hud:
            return "HUD"
        case .music:
            return "音乐"
        case .watchFace:
            return "表盘"
        case .detection:
            return "系统检测"
        case .about:
            return "关于"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "gearshape.fill"
        case .mouse:
            return "computermouse.fill"
        case .hud:
            return "slider.horizontal.3"
        case .music:
            return "music.note"
        case .watchFace:
            return "applewatch"
        case .detection:
            return "eye.fill"
        case .about:
            return "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general:
            return Color(red: 0.48, green: 0.52, blue: 0.62)
        case .mouse:
            return Color(red: 0.22, green: 0.64, blue: 0.72)
        case .hud:
            return Color(red: 0.66, green: 0.40, blue: 1.00)
        case .music:
            return Color(red: 1.00, green: 0.34, blue: 0.38)
        case .watchFace:
            return Color(red: 0.22, green: 0.78, blue: 0.48)
        case .detection:
            return Color(red: 1.00, green: 0.62, blue: 0.20)
        case .about:
            return Color(red: 0.52, green: 0.55, blue: 0.62)
        }
    }
}
private enum HUDPage: String, CaseIterable, Identifiable {
    case volume
    case lighting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .volume:
            return "音量"
        case .lighting:
            return "亮度与键盘"
        }
    }
}

private enum IconSettingsPage: String, CaseIterable, Identifiable {
    case menuBar
    case application

    var id: String { rawValue }

    var title: String {
        switch self {
        case .menuBar:
            return "菜单栏"
        case .application:
            return "应用"
        }
    }
}

private enum NotchBackgroundVisibility: String, CaseIterable, Identifiable {
    case off
    case playback
    case always

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            return "关闭"
        case .playback:
            return "播放时"
        case .always:
            return "始终显示"
        }
    }
}

struct SettingsView: View {
    private static var lastSelectedCategory = SettingsCategory.general

    @State private var selectedCategory = SettingsView.lastSelectedCategory
    @State private var selectedHUDPage = HUDPage.volume
    @State private var selectedIconSettingsPage = IconSettingsPage.menuBar
    @State private var isPointerInsideSettings = false
    @State private var selectedMusicControlSlot: Int?
    @State private var watchFaceCropEditor: WatchFaceCropEditorState?
    @State private var watchFaceImageError: String?
    @State private var draftNotchWidthAdjustment = 0
    @State private var draftNotchHeightAdjustment = 0
    @State private var isNotchPreviewing = false
    @FocusState private var isEmojiFieldFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var musicMonitor: MusicMonitor
    @EnvironmentObject private var systemActivityMonitor: SystemActivityMonitor
    @EnvironmentObject private var systemHUDController: SystemHUDController
    @EnvironmentObject private var mouseScrollController: MouseScrollController
    @AppStorage(SystemHUDSettings.style)
    private var systemHUDStyleRaw = SystemHUDStyle.customOSD.rawValue
    @AppStorage(SystemHUDSettings.volumeEnabled)
    private var volumeHUDEnabled = true
    @AppStorage(SystemHUDSettings.brightnessEnabled)
    private var brightnessHUDEnabled = true
    @AppStorage(SystemHUDSettings.keyboardBrightnessEnabled)
    private var keyboardBrightnessHUDEnabled = true
    @AppStorage(SystemHUDSettings.audioFeedbackEnabled)
    private var audioFeedbackEnabled = false
    @AppStorage(SystemHUDSettings.hapticFeedbackEnabled)
    private var hapticFeedbackEnabled = false
    @AppStorage(SystemHUDSettings.nativeControlsVisible)
    private var showsNativeSystemControls = false
    @AppStorage(SystemHUDSettings.volumeStep)
    private var volumeStep = 5
    @AppStorage(SystemHUDSettings.volumeFineStep)
    private var volumeFineStep = 2
    @AppStorage(SystemHUDSettings.brightnessStep)
    private var brightnessStep = 5
    @AppStorage(SystemHUDSettings.brightnessFineStep)
    private var brightnessFineStep = 2
    @AppStorage(LightingHUDSettings.duration)
    private var lightingHUDDuration = LightingHUDSettings.defaultDuration
    @AppStorage(LightingHUDSettings.style)
    private var lightingHUDStyleRaw = LightingHUDStyle.glow.rawValue
    @AppStorage(LightingHUDSettings.speed)
    private var lightingHUDSpeedRaw = SoundHUDSpeed.smooth.rawValue
    @AppStorage(LightingHUDSettings.showsPercentage)
    private var lightingHUDShowsPercentage = true
    @AppStorage(LightingHUDSettings.hidesLabel)
    private var lightingHUDHidesLabel = false
    @AppStorage(SoundHUDSettings.duration)
    private var soundHUDDuration = SoundHUDSettings.defaultDuration
    @AppStorage(SoundHUDSettings.style)
    private var soundHUDStyleRaw = SoundHUDStyle.decibel.rawValue
    @AppStorage(SoundHUDSettings.speed)
    private var soundHUDSpeedRaw = SoundHUDSpeed.smooth.rawValue
    @AppStorage(SoundHUDSettings.showsPercentage)
    private var soundHUDShowsPercentage = true
    @AppStorage(SoundHUDSettings.hidesLabel)
    private var soundHUDHidesLabel = false
    @AppStorage(SoundHUDSettings.content)
    private var soundHUDContentRaw = SoundHUDContent.device.rawValue
    @AppStorage(MusicSpectrumSettings.enabled)
    private var musicSpectrumEnabled = true
    @AppStorage(MusicControlLayoutSettings.storageKey)
    private var musicControlLayoutRaw =
        MusicControlLayoutSettings.defaultRawValue
    @AppStorage(ProgressTrackStyle.storageKey)
    private var progressTrackStyleRaw = ProgressTrackStyle.softAurora.rawValue
    @AppStorage(NotchBackgroundSettings.enabled)
    private var notchBackgroundEnabled = true
    @AppStorage(NotchBackgroundSettings.effect)
    private var notchBackgroundEffectRaw = NotchBackgroundEffect.aurora.rawValue
    @AppStorage(NotchBackgroundSettings.alwaysVisible)
    private var notchBackgroundAlwaysVisible = false
    @AppStorage(NotchLayout.alwaysExpanded)
    private var keepsNotchExpanded = false
    @AppStorage(WatchFaceStyle.storageKey)
    private var watchFaceStyleRaw = WatchFaceStyle.classic.rawValue
    @AppStorage(WatchFaceDisplaySettings.showsInMusicKey)
    private var showsWatchFaceInMusic = true
    @AppStorage(MultiAvatarSettings.seedKey)
    private var avatarSeed = MultiAvatarSettings.defaultSeed
    @AppStorage(WatchFaceEmojiSettings.storageKey)
    private var watchFaceEmoji = WatchFaceEmojiSettings.defaultEmoji
    @AppStorage(WatchFaceImageSettings.pathKey)
    private var watchFaceImagePath = ""
    @AppStorage(WatchFaceImageSettings.cropKey)
    private var watchFaceImageCropRawValue = ""
    @AppStorage(WatchFaceClockSettings.uses24HourKey)
    private var uses24HourClock = true
    @AppStorage(SystemDetectionSettings.screenRecordingDetection)
    private var screenRecordingDetectionEnabled = true
    @AppStorage(SystemDetectionSettings.screenRecordingIndicator)
    private var showsScreenRecordingIndicator = true
    @AppStorage(SystemDetectionSettings.focusDetection)
    private var focusDetectionEnabled = true
    @AppStorage(SystemDetectionSettings.focusIndicator)
    private var showsFocusIndicator = true
    @AppStorage(SystemDetectionSettings.focusLabel)
    private var showsFocusLabel = true
    @AppStorage(SystemDetectionSettings.focusCompactHint)
    private var usesCompactFocusHint = false
    @AppStorage(SystemDetectionSettings.capsLockIndicator)
    private var showsCapsLockIndicator = true
    @AppStorage(SystemDetectionSettings.capsLockLabel)
    private var showsCapsLockLabel = true
    @AppStorage(SystemDetectionSettings.capsLockColor)
    private var capsLockColorRaw = CapsLockIndicatorColor.blue.rawValue
    @AppStorage(SystemDetectionSettings.cameraDetection)
    private var cameraDetectionEnabled = true
    @AppStorage(SystemDetectionSettings.microphoneDetection)
    private var microphoneDetectionEnabled = true
    @AppStorage(NotchLayout.physicalNotchOutline)
    private var showsPhysicalNotchOutline = false
    @AppStorage(NotchLayout.notchWidthAdjustment)
    private var notchWidthAdjustmentValue = 0
    @AppStorage(NotchLayout.notchHeightAdjustment)
    private var notchHeightAdjustmentValue = 0
    @AppStorage(NotchLayout.notchPreviewWidth)
    private var notchPreviewWidthValue = 0
    @AppStorage(NotchLayout.notchPreviewHeight)
    private var notchPreviewHeightValue = 0
    @AppStorage(NotchLayout.notchPreviewActive)
    private var notchPreviewActiveValue = false
    @AppStorage(MenuBarIconStyle.storageKey)
    private var menuBarIconStyleRaw = MenuBarIconStyle.notch.rawValue
    @AppStorage(ApplicationIconStyle.storageKey)
    private var applicationIconStyleRaw = ApplicationIconStyle.ocean.rawValue
    @AppStorage(MouseScrollSettings.activeKey)
    private var mouseScrollActive = true
    @AppStorage(MouseScrollSettings.enabledKey)
    private var mouseScrollSmoothingEnabled = true
    @AppStorage(MouseScrollSettings.reverseVerticalKey)
    private var mouseScrollReverseVertical = false
    @AppStorage(MouseScrollSettings.reverseHorizontalKey)
    private var mouseScrollReverseHorizontal = false
    @AppStorage(MouseScrollSettings.speedKey)
    private var mouseScrollSpeed = 2.90
    @AppStorage(MouseScrollSettings.durationKey)
    private var mouseScrollDuration = 4.50

    private let watchFaceEmojiOptions = [
        "😀", "😎", "🥰", "😂", "🤩", "😴", "🤖", "👻",
        "🐶", "🐱", "🐼", "🦊", "🐸", "🌈", "⚡️", "✨"
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            SettingsBackdrop()

            VStack(spacing: 0) {
                Group {
                    if selectedCategory == .about {
                        selectedSettingsContent
                    } else {
                        ScrollView {
                            selectedSettingsContent
                        }
                        .padding(.top, 16)
                        .padding(.bottom, 16)
                        .scrollIndicators(.visible)
                        .id(selectedCategory)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            SettingsSidebar(selectedCategory: $selectedCategory)
                .padding(.leading, 12)
                .frame(maxHeight: .infinity, alignment: .center)
                .zIndex(2)
        }
        .frame(width: 520, height: 720)
        .environment(
            \.settingsPreviewsActive,
            isPointerInsideSettings
        )
        .onHover { hovering in
            if isPointerInsideSettings != hovering {
                isPointerInsideSettings = hovering
            }
        }
        .onAppear {
            musicMonitor.refreshNow()
            systemHUDController.refreshAvailability()
            mouseScrollController.refreshAvailability()
            draftNotchWidthAdjustment = notchWidthAdjustmentValue
            draftNotchHeightAdjustment = notchHeightAdjustmentValue
            endNotchPreview()
        }
        .onDisappear {
            endNotchPreview()
        }
        .onChange(of: selectedCategory) { _, category in
            SettingsView.lastSelectedCategory = category
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            systemHUDController.refreshAvailability()
            mouseScrollController.refreshAvailability()
        }
        .sheet(item: $watchFaceCropEditor) { editor in
            WatchFaceCropEditor(
                image: editor.image,
                initialCrop: editor.initialCrop,
                onCancel: {
                    watchFaceCropEditor = nil
                },
                onConfirm: { crop in
                    applyWatchFaceCrop(crop, editor: editor)
                    watchFaceCropEditor = nil
                }
            )
        }
    }

    @ViewBuilder
    private var selectedSettingsContent: some View {
        Group {
            switch selectedCategory {
            case .general:
                VStack(spacing: 12) {
                    glassCard {
                        iconSettingsSection
                    }

                    glassCard {
                        notchBehaviorSection
                    }
                }

            case .mouse:
                glassCard {
                    mouseScrollSection
                }

            case .hud:
                VStack(spacing: 12) {
                    glassCard {
                        systemHUDStyleSection
                    }

                    hudPagePicker

                    if selectedHUDPage == .volume {
                        glassCard {
                            soundNotificationSection
                        }

                        glassCard {
                            soundControlsSection
                        }
                    } else {
                        glassCard {
                            lightingNotificationSection
                        }

                        glassCard {
                            lightingDetailsSection
                        }
                    }

                    glassCard {
                        systemHUDControlsSection
                    }
                }

            case .music:
                VStack(spacing: 12) {
                    glassCard {
                        musicSection
                    }

                    glassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            progressTrackSection

                            Divider()
                                .opacity(0.5)

                            musicSpectrumSection
                        }
                    }

                    glassCard {
                        notchBackgroundSection
                    }

                    glassCard {
                        musicControlsSection
                    }

                }

            case .watchFace:
                glassCard {
                    watchFaceSection
                }

            case .detection:
                glassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionHeader(
                            title: "状态指示器",
                            systemImage: "switch.2"
                        )

                        Text("统一管理屏幕录制、专注模式、Caps Lock 与隐私状态在灵动岛中的显示。")
                            .settingsCaption()

                        Divider()
                            .opacity(0.5)

                        screenRecordingSection

                        Divider()
                            .opacity(0.5)

                        focusModeSection

                        Divider()
                            .opacity(0.5)

                        capsLockSection

                        Divider()
                            .opacity(0.5)

                        privacyIndicatorsSection
                    }
                }

            case .about:
                ZStack {
                    ConfettiLayer()
                        .clipped()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)

                    VStack(spacing: 0) {
                        Spacer(minLength: 0)

                        VStack(spacing: 20) {
                            appLogo

                            VStack(spacing: 5) {
                                appName

                                appTagline
                                    .multilineTextAlignment(.center)
                            }

                            privacyNotice

                            aboutLinks
                        }
                        .frame(maxWidth: 380)
                        .transition(
                            .asymmetric(
                                insertion: .offset(x: 0, y: -220)
                                    .combined(with: .opacity),
                                removal: .opacity
                            )
                        )

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.leading, 74)
        .padding(.trailing, 20)
    }

    private var appLogo: some View {
        Image(selectedApplicationIconStyle.assetName)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: 64, height: 64)
            .shadow(color: .black.opacity(0.28), radius: 8, y: 4)
            .accessibilityHidden(true)
    }

    private var appName: some View {
        SparklesText(text: "NotchMusic")
            .font(.system(size: 20, weight: .bold, design: .rounded))
    }

    private var appTagline: some View {
        Text("在灵动岛里显示 Apple Music 当前播放的歌曲")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }

    private var systemHUDStyleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader(
                    title: "系统 HUD",
                    systemImage: "slider.horizontal.3"
                )

                Spacer()

                Text(selectedSystemHUDStyle.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 8),
                    count: SystemHUDStyle.allCases.count
                ),
                spacing: 8
            ) {
                ForEach(SystemHUDStyle.allCases) { style in
                    systemHUDStyleButton(style)
                }
            }

            Text(
                "选择系统 HUD 的布局。音量与灯光的样式、时长和反馈在下方标签中设置。"
            )
                .settingsCaption()
        }
    }

    private var hudPagePicker: some View {
        SettingsPageTabs(
            titles: HUDPage.allCases.map(\.title),
            selectedIndex: HUDPage.allCases.firstIndex(of: selectedHUDPage) ?? 0
        ) { index in
            selectedHUDPage = HUDPage.allCases[index]
        }
    }

    private var systemHUDControlsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "控制",
                systemImage: "dial.medium.fill"
            )

            settingToggle(
                title: "显示系统原生控制",
                detail: "开启后音量、亮度键交由 macOS 处理；关闭后由灵动岛 HUD 接管",
                systemImage: "rectangle.slash",
                isOn: $showsNativeSystemControls
            )

            Text(
                showsNativeSystemControls
                    ? "当前保留 macOS 原生控制；系统变化仍会同步显示在灵动岛 HUD。"
                    : systemHUDController.accessibilityGranted
                        ? "原生控制已隐藏；硬件键由 NotchMusic 接管并使用自定义步长。"
                        : "隐藏原生控制需要辅助功能权限；未授权时 macOS 仍会显示原生控制。"
            )
                .settingsCaption()

            HStack(spacing: 8) {
                Circle()
                    .fill(
                        systemHUDController.interceptionActive
                            || systemHUDController.passiveMonitoringActive
                            ? Color.green
                            : Color.orange
                    )
                    .frame(width: 6, height: 6)

                Text(
                    systemHUDController.interceptionActive
                        ? "硬件键拦截已启用"
                        : systemHUDController.passiveMonitoringActive
                            ? "被动 HUD 监测已启用"
                            : "暂无可监测的系统控件"
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

                Spacer()

                if !systemHUDController.accessibilityGranted {
                    Button("授予权限") {
                        systemHUDController.requestAccessibilityPermission()
                    }
                    .controlSize(.small)
                }

                Button("系统设置") {
                    systemHUDController.openAccessibilitySettings()
                }
                .controlSize(.small)
            }
        }
    }

    private var selectedLightingStyle: LightingHUDStyle {
        LightingHUDStyle(rawValue: lightingHUDStyleRaw) ?? .glow
    }

    private var selectedLightingSpeed: SoundHUDSpeed {
        SoundHUDSpeed(rawValue: lightingHUDSpeedRaw) ?? .smooth
    }

    private var lightingNotificationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "灯光",
                systemImage: "sun.max.fill"
            )

            Text("调整屏幕亮度或键盘背光时在灵动岛显示灯光通知。")
                .settingsCaption()

            soundToggleRow(
                title: "显示器亮度",
                isOn: $brightnessHUDEnabled
            )
            .disabled(!systemHUDController.availability.displayBrightness)
            .opacity(
                systemHUDController.availability.displayBrightness ? 1 : 0.48
            )

            soundToggleRow(
                title: "键盘背光",
                isOn: $keyboardBrightnessHUDEnabled
            )
            .disabled(!systemHUDController.availability.keyboardBrightness)
            .opacity(
                systemHUDController.availability.keyboardBrightness ? 1 : 0.48
            )

            Divider()
                .opacity(0.5)

            HStack {
                Text("持续时间")
                    .font(.system(size: 12, weight: .medium))

                Spacer()

                Text(String(format: "%.1f s", lightingHUDDuration))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.07), in: Capsule())
            }

            Slider(
                value: $lightingHUDDuration,
                in: 0.5...5,
                step: 0.5
            )
            .tint(.accentColor)

            HStack {
                Text("0.5 s")
                Spacer()
                Text("5.0 s")
            }
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(.tertiary)

            HStack(spacing: 8) {
                ForEach(LightingHUDStyle.allCases) { style in
                    LightingStyleButton(
                        style: style,
                        speed: selectedLightingSpeed,
                        isSelected: selectedLightingStyle == style
                    ) {
                        lightingHUDStyleRaw = style.rawValue
                    }
                }
            }

            Text("“强调色”沿用显示器暖黄与键盘背光蓝色；“光晕”为纯白渐变光柱。")
                .settingsCaption()

            soundToggleRow(
                title: "显示百分比",
                isOn: $lightingHUDShowsPercentage
            )
            soundToggleRow(
                title: "隐藏标签",
                isOn: $lightingHUDHidesLabel
            )

            Divider()
                .opacity(0.5)

            Text("动画速度")
                .font(.system(size: 12, weight: .medium))

            HStack(spacing: 8) {
                ForEach(SoundHUDSpeed.allCases) { speed in
                    lightingSpeedButton(speed)
                }
            }

            Text("HUD 布局可在本页顶部切换。")
                .settingsCaption()
        }
    }

    private var lightingDetailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "亮度",
                systemImage: "dial.medium.fill"
            )

            stepSlider(
                title: "亮度步长",
                value: $brightnessStep
            )
            stepSlider(
                title: "亮度微调步长",
                value: $brightnessFineStep
            )

            Text("按住 Option + Shift 调整亮度键可使用微调步长。")
                .settingsCaption()

            Text(hardwareStatusText)
                .settingsCaption()
        }
    }

    private var selectedSoundStyle: SoundHUDStyle {
        SoundHUDStyle(rawValue: soundHUDStyleRaw) ?? .decibel
    }

    private var selectedSoundSpeed: SoundHUDSpeed {
        SoundHUDSpeed(rawValue: soundHUDSpeedRaw) ?? .smooth
    }

    private var selectedSoundContent: SoundHUDContent {
        SoundHUDContent(rawValue: soundHUDContentRaw) ?? .device
    }

    private var soundNotificationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                sectionHeader(
                    title: "声音",
                    systemImage: "speaker.wave.2.fill"
                )

                Spacer()

                Toggle("", isOn: $volumeHUDEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(.accentColor)
                    .disabled(!systemHUDController.availability.volume)
                    .opacity(
                        systemHUDController.availability.volume ? 1 : 0.48
                    )
            }

            Text("调整音量时在灵动岛显示声音通知。")
                .settingsCaption()

            Divider()
                .opacity(0.5)

            HStack {
                Text("持续时间")
                    .font(.system(size: 12, weight: .medium))

                Spacer()

                Text(String(format: "%.1f s", soundHUDDuration))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.07), in: Capsule())
            }

            Slider(
                value: $soundHUDDuration,
                in: 0.5...5,
                step: 0.5
            )
            .tint(.accentColor)

            HStack {
                Text("0.5 s")
                Spacer()
                Text("5.0 s")
            }
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(.tertiary)

            HStack(spacing: 8) {
                ForEach(SoundHUDStyle.allCases) { style in
                    SoundStyleButton(
                        style: style,
                        speed: selectedSoundSpeed,
                        isSelected: selectedSoundStyle == style
                    ) {
                        soundHUDStyleRaw = style.rawValue
                    }
                }
            }

            Text("“跟随封面”会取专辑封面主色；“分贝”会随音量从绿色过渡到红色。")
                .settingsCaption()

            soundToggleRow(
                title: "显示百分比",
                isOn: $soundHUDShowsPercentage
            )
            soundToggleRow(
                title: "隐藏标签",
                isOn: $soundHUDHidesLabel
            )

            Divider()
                .opacity(0.5)

            Text("动画速度")
                .font(.system(size: 12, weight: .medium))

            HStack(spacing: 8) {
                ForEach(SoundHUDSpeed.allCases) { speed in
                    soundSpeedButton(speed)
                }
            }

            Divider()
                .opacity(0.5)

            Text("图标")
                .font(.system(size: 12, weight: .medium))

            HStack(spacing: 8) {
                ForEach(SoundHUDContent.allCases) { content in
                    soundContentButton(content)
                }
            }

            Text("HUD 布局可在本页顶部切换。")
                .settingsCaption()
        }
    }

    private var soundControlsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "按键与反馈",
                systemImage: "dial.medium.fill"
            )

            settingToggle(
                title: "音频反馈",
                detail: "调整音量时播放轻量反馈音",
                systemImage: "speaker.badge.plus",
                isOn: $audioFeedbackEnabled
            )

            settingToggle(
                title: "触感反馈",
                detail: "调整音量时在触控板上提供轻微震动",
                systemImage: "hand.tap.fill",
                isOn: $hapticFeedbackEnabled
            )

            stepSlider(
                title: "音量步长",
                value: $volumeStep
            )
            stepSlider(
                title: "音量微调步长",
                value: $volumeFineStep
            )

            Text("按住 Option + Shift 调整音量键可使用微调步长。")
                .settingsCaption()

            if !systemHUDController.interceptionActive {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)

                    Text(
                        showsNativeSystemControls
                            ? "“显示系统原生控制”已开启，音量键由 macOS 处理，步长不会生效。"
                            : "当前未获得辅助功能权限，音量键仍由 macOS 处理；授权后步长才会生效。"
                    )
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Spacer()

                    if !systemHUDController.accessibilityGranted {
                        Button("授予权限") {
                            systemHUDController
                                .requestAccessibilityPermission()
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private func speedStyleButton(
        _ speed: SoundHUDSpeed,
        isSelected: Bool,
        accessibilityLabel: String,
        onSelect: @escaping () -> Void
    ) -> some View {
        Button(action: onSelect) {
            VStack(spacing: 5) {
                Image(systemName: speed.systemImage)
                    .font(.system(size: 13, weight: .semibold))

                Text(speed.displayName)
                    .font(.system(size: 9.5, weight: .medium))
            }
            .foregroundStyle(
                isSelected ? Color.accentColor : Color.secondary
            )
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .settingsSelectionCard(
                isSelected: isSelected,
                cornerRadius: 12,
                selectedBorderOpacity: 0.72
            )
            .contentShape(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .help(speed.displayName)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func lightingSpeedButton(_ speed: SoundHUDSpeed) -> some View {
        speedStyleButton(
            speed,
            isSelected: selectedLightingSpeed == speed,
            accessibilityLabel: "灯光动画速度 \(speed.displayName)"
        ) {
            lightingHUDSpeedRaw = speed.rawValue
        }
    }

    private func soundSpeedButton(_ speed: SoundHUDSpeed) -> some View {
        speedStyleButton(
            speed,
            isSelected: selectedSoundSpeed == speed,
            accessibilityLabel: "动画速度 \(speed.displayName)"
        ) {
            soundHUDSpeedRaw = speed.rawValue
        }
    }

    private func soundContentButton(_ content: SoundHUDContent) -> some View {
        let isSelected = selectedSoundContent == content

        return Button {
            soundHUDContentRaw = content.rawValue
        } label: {
            SoundIconPreview(content: content)
                .frame(height: 38)
                .padding(4)
                .frame(maxWidth: .infinity)
                .settingsSelectionCard(
                    isSelected: isSelected,
                    cornerRadius: 12,
                    selectedBorderOpacity: 0.72
                )
                .contentShape(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .help(content.displayName)
        .accessibilityLabel(content.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func soundToggleRow(
        title: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium))

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(.accentColor)
        }
    }

    private var musicSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Apple Music")
                .font(.system(size: 13, weight: .semibold))

            Text(statusText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                if musicMonitor.isConnected {
                    Button("断开连接") {
                        musicMonitor.disconnect()
                    }

                    Button("打开 Apple Music") {
                        musicMonitor.openAppleMusic()
                    }
                } else {
                    Button("连接 Apple Music") {
                        musicMonitor.connect()
                    }
                }

                if musicMonitor.needsPermission {
                    Button("打开自动化设置") {
                        musicMonitor.openAutomationSettings()
                    }
                }
            }
        }
    }

    private var iconSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader(
                    title: "图标",
                    systemImage: "app.dashed"
                )

                Spacer()

                Text(
                    selectedIconSettingsPage == .menuBar
                        ? MenuBarIconStyle(
                            rawValue: menuBarIconStyleRaw
                        )?.displayName ?? ""
                        : selectedApplicationIconStyle.displayName
                )
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            iconSettingsPagePicker

            if selectedIconSettingsPage == .menuBar {
                menuBarIconContent
            } else {
                applicationIconContent
            }
        }
    }

    private var iconSettingsPagePicker: some View {
        SettingsPageTabs(
            titles: IconSettingsPage.allCases.map(\.title),
            selectedIndex: IconSettingsPage.allCases.firstIndex(
                of: selectedIconSettingsPage
            ) ?? 0
        ) { index in
            selectedIconSettingsPage = IconSettingsPage.allCases[index]
        }
    }

    private var menuBarIconContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 6),
                    count: 7
                ),
                spacing: 6
            ) {
                ForEach(MenuBarIconStyle.allCases) { style in
                    menuBarIconButton(style)
                }
            }

            Text("选择后菜单栏图标会立即更新，无需重新启动应用。")
                .settingsCaption()
        }
    }

    private func menuBarIconButton(
        _ style: MenuBarIconStyle
    ) -> some View {
        let isSelected = style.rawValue == menuBarIconStyleRaw

        return Button {
            menuBarIconStyleRaw = style.rawValue
        } label: {
            menuBarIconGlyph(style)
                .foregroundStyle(
                    isSelected ? Color.accentColor : Color.primary.opacity(0.72)
                )
                .frame(width: 48, height: 48)
                .settingsSelectionCard(
                    isSelected: isSelected,
                    cornerRadius: 10
                )
                .contentShape(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .help(style.displayName)
        .accessibilityLabel("菜单栏图标 \(style.displayName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func menuBarIconGlyph(
        _ style: MenuBarIconStyle
    ) -> some View {
        if style == .notch {
            Image(nsImage: MenuBarIconRenderer.notchIcon)
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 20, height: 20)
                .frame(height: 22)
        } else {
            Image(systemName: style.systemImage ?? "music.note")
                .font(.system(size: 19, weight: .semibold))
                .frame(height: 22)
        }
    }

    private var applicationIconContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 8),
                    count: 5
                ),
                spacing: 8
            ) {
                ForEach(ApplicationIconStyle.allCases) { style in
                    applicationIconButton(style)
                }
            }

            Text("选择后运行中的应用图标会立即更新；访达中的应用文件图标由安装包固定，不会随此项变化。")
                .settingsCaption()
        }
    }

    private func applicationIconButton(
        _ style: ApplicationIconStyle
    ) -> some View {
        let isSelected = style.rawValue == applicationIconStyleRaw

        return Button {
            applicationIconStyleRaw = style.rawValue
        } label: {
            VStack(spacing: 5) {
                Image(style.assetName)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
                    .shadow(
                        color: .black.opacity(0.22),
                        radius: 4,
                        y: 2
                    )

                Text(style.displayName)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(width: 70, height: 70)
            .settingsSelectionCard(
                isSelected: isSelected,
                cornerRadius: 12
            )
            .contentShape(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .help(style.displayName)
        .accessibilityLabel("应用图标 \(style.displayName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var selectedApplicationIconStyle: ApplicationIconStyle {
        ApplicationIconStyle(rawValue: applicationIconStyleRaw) ?? .ocean
    }

    private var notchBehaviorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "灵动岛显示",
                systemImage: "menubar.rectangle"
            )

            settingToggle(
                title: "始终展开灵动岛",
                detail: "保持显示完整音乐面板，鼠标移开后不会自动收起",
                systemImage: "pin.fill",
                isOn: $keepsNotchExpanded
            )

            Text("关闭后会恢复为悬停展开，鼠标移开时自动收起。")
                .settingsCaption()

            Divider()
                .opacity(0.5)

            settingToggle(
                title: "显示物理灵动岛轮廓",
                detail: "在灵动岛面板上用虚线标出摄像头灵动岛的真实位置",
                systemImage: "rectangle.dashed",
                isOn: $showsPhysicalNotchOutline
            )

            Divider()
                .opacity(0.5)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("刘海尺寸校准")
                        .font(.system(size: 11.5, weight: .medium))

                    Spacer()

                    Text(isNotchPreviewing ? "预览中" : "自动")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(
                            isNotchPreviewing ? Color.red : Color.secondary
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            isNotchPreviewing
                                ? Color.red.opacity(0.12)
                                : Color.primary.opacity(0.07),
                            in: Capsule()
                        )
                }

                notchAdjustmentSlider(
                    title: "宽度",
                    value: $draftNotchWidthAdjustment,
                    limit: NotchLayout.notchWidthAdjustmentLimit
                )

                notchAdjustmentSlider(
                    title: "高度",
                    value: $draftNotchHeightAdjustment,
                    limit: NotchLayout.notchHeightAdjustmentLimit
                )

                Text("拖动时屏幕顶部会显示红色预览框，确认无误后点「应用」才会生效。")
                    .settingsCaption()

                HStack(spacing: 8) {
                    Button("恢复自动") {
                        draftNotchWidthAdjustment = 0
                        draftNotchHeightAdjustment = 0
                    }
                    .controlSize(.small)
                    .disabled(
                        draftNotchWidthAdjustment == 0
                            && draftNotchHeightAdjustment == 0
                    )

                    Spacer()

                    Button("取消") {
                        cancelNotchPreview()
                    }
                    .controlSize(.small)
                    .disabled(!isNotchPreviewing)

                    Button("应用") {
                        applyNotchPreview()
                    }
                    .controlSize(.small)
                    .disabled(!isNotchPreviewing)
                }
            }
            .onChange(of: draftNotchWidthAdjustment) { _, _ in
                updateNotchPreview()
            }
            .onChange(of: draftNotchHeightAdjustment) { _, _ in
                updateNotchPreview()
            }
        }
    }

    private func notchAdjustmentSlider(
        title: String,
        value: Binding<Int>,
        limit: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(
                    value.wrappedValue == 0
                        ? "自动"
                        : String(format: "%+d pt", value.wrappedValue)
                )
                .font(.system(size: 10.5, weight: .semibold))
                .monospacedDigit()
            }

            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0.rounded()) }
                ),
                in: -Double(limit)...Double(limit),
                step: 1
            )
            .tint(.accentColor)
        }
    }

    private func updateNotchPreview() {
        guard draftNotchWidthAdjustment != notchWidthAdjustmentValue
                || draftNotchHeightAdjustment != notchHeightAdjustmentValue
        else {
            endNotchPreview()
            return
        }

        isNotchPreviewing = true
        notchPreviewWidthValue = draftNotchWidthAdjustment
        notchPreviewHeightValue = draftNotchHeightAdjustment
        notchPreviewActiveValue = true
    }

    private func endNotchPreview() {
        isNotchPreviewing = false
        notchPreviewActiveValue = false
    }

    private func cancelNotchPreview() {
        draftNotchWidthAdjustment = notchWidthAdjustmentValue
        draftNotchHeightAdjustment = notchHeightAdjustmentValue
        endNotchPreview()
    }

    private func applyNotchPreview() {
        notchWidthAdjustmentValue = draftNotchWidthAdjustment
        notchHeightAdjustmentValue = draftNotchHeightAdjustment
        endNotchPreview()
    }

    private var progressTrackSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader(
                    title: "进度条样式",
                    systemImage: "capsule.portrait"
                )

                Spacer()

                Text(selectedProgressTrackStyle.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 8),
                    count: 2
                ),
                spacing: 8
            ) {
                ForEach(ProgressTrackStyle.allCases) { style in
                    progressTrackStyleButton(style)
                }
            }

            Text("样式会立即应用到灵动岛中的播放进度条，并在播放时呈现对应动画。")
                .settingsCaption()
        }
    }

    private func progressTrackStyleButton(
        _ style: ProgressTrackStyle
    ) -> some View {
        let isSelected = style == selectedProgressTrackStyle

        return Button {
            progressTrackStyleRaw = style.rawValue
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                progressTrackStylePreview(style)
                    .frame(height: 16)

                HStack(spacing: 6) {
                    Image(systemName: style.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(
                            isSelected ? Color.accentColor : .secondary
                        )

                    Text(style.displayName)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)

                    Spacer(minLength: 2)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(9)
            .settingsSelectionCard(
                isSelected: isSelected,
                cornerRadius: 12
            )
            .contentShape(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .help(style.displayName)
        .accessibilityLabel("播放进度条 \(style.displayName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func progressTrackStylePreview(
        _ style: ProgressTrackStyle
    ) -> some View {
        GeometryReader { geometry in
            let fillWidth = max(geometry.size.width * 0.68, 14)

            ZStack(alignment: .leading) {
                if style == .classic {
                    Capsule()
                        .fill(Color.black.opacity(0.3))
                        .frame(height: 5)
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    Color.primary.opacity(0.12),
                                    lineWidth: 0.55
                                )
                        }

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    progressTrackAccent.opacity(0.58),
                                    progressTrackAccent,
                                    progressTrackAccent.opacity(0.82)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fillWidth, height: 5)
                        .overlay(alignment: .topLeading) {
                            Capsule()
                                .fill(Color.white.opacity(0.24))
                                .frame(height: 1)
                                .padding(.horizontal, 3)
                                .padding(.top, 1)
                        }
                        .clipShape(Capsule())
                        .shadow(
                            color: progressTrackAccent.opacity(0.34),
                            radius: 3,
                            y: 1
                        )
                } else {
                    SoftAuroraProgressTrack(
                        color: progressTrackAccent,
                        isPlaying: isPointerInsideSettings
                            && style == selectedProgressTrackStyle,
                        isActive: false
                    )
                    .frame(width: geometry.size.width, height: 10)
                    .mask {
                        Rectangle()
                            .frame(width: fillWidth, height: 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .shadow(
                        color: progressTrackAccent.opacity(0.4),
                        radius: 3,
                        y: 1
                    )
                }

                if style == .classic {
                    Circle()
                        .fill(progressTrackAccent)
                        .frame(width: 10, height: 10)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    Color.white.opacity(0.86),
                                    lineWidth: 1
                                )
                        }
                        .offset(x: fillWidth - 4)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var notchBackgroundSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader(
                    title: "动态背景",
                    systemImage: "sparkles"
                )

                Spacer()

                Text(selectedNotchBackgroundEffect.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("显示时机")
                    .font(.system(size: 12, weight: .medium))

                Spacer()

                SettingsPageTabs(
                    titles: NotchBackgroundVisibility.allCases.map(\.title),
                    selectedIndex: NotchBackgroundVisibility.allCases
                        .firstIndex(
                            of: notchBackgroundVisibility.wrappedValue
                        ) ?? 0
                ) { index in
                    notchBackgroundVisibility.wrappedValue =
                        NotchBackgroundVisibility.allCases[index]
                }
                .frame(width: 238)
            }

            Divider()
                .opacity(0.5)

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 8),
                    count: 4
                ),
                spacing: 8
            ) {
                ForEach(NotchBackgroundEffect.allCases) { effect in
                    notchBackgroundEffectButton(effect)
                }
            }

            Text(notchBackgroundSummary)
                .settingsCaption()
        }
    }

    private var notchBackgroundSummary: String {
        if selectedNotchBackgroundEffect == .albumFlow {
            switch notchBackgroundVisibility.wrappedValue {
            case .off:
                return "底部动态背景已关闭。"
            case .playback:
                return "背景会流动展示资料库中的专辑封面，并在暂停播放时淡出。"
            case .always:
                return "背景会流动展示资料库中的专辑封面，并始终保持显示。"
            }
        }

        switch notchBackgroundVisibility.wrappedValue {
        case .off:
            return "底部动态背景已关闭。"
        case .playback:
            return "背景动画会跟随当前专辑封面主色，并在暂停播放时淡出。"
        case .always:
            return "背景动画会跟随当前专辑封面主色，并始终保持显示。"
        }
    }

    private func notchBackgroundEffectButton(
        _ effect: NotchBackgroundEffect
    ) -> some View {
        let isSelected = effect == selectedNotchBackgroundEffect

        return Button {
            notchBackgroundEffectRaw = effect.rawValue
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    notchBackgroundAccent.opacity(
                                        isSelected ? 0.46 : 0.20
                                    ),
                                    Color.black.opacity(0.48)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Image(systemName: effect.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(
                            isSelected
                                ? Color.white
                                : Color.primary.opacity(0.72)
                        )
                }
                .frame(height: 34)

                Text(effect.displayName)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
            .frame(maxWidth: .infinity)
            .padding(7)
            .settingsSelectionCard(
                isSelected: isSelected,
                cornerRadius: 12
            )
            .contentShape(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .help(effect.displayName)
        .accessibilityLabel("动态背景 \(effect.displayName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var notchBackgroundAccent: Color {
        Color(
            nsColor: musicMonitor.snapshot?.accentColor
                ?? ArtworkPalette.fallback
        )
    }

    private var selectedNotchBackgroundEffect: NotchBackgroundEffect {
        NotchBackgroundEffect(rawValue: notchBackgroundEffectRaw) ?? .aurora
    }

    private var notchBackgroundVisibility:
        Binding<NotchBackgroundVisibility> {
        Binding(
            get: {
                guard notchBackgroundEnabled else { return .off }
                return notchBackgroundAlwaysVisible ? .always : .playback
            },
            set: { visibility in
                notchBackgroundEnabled = visibility != .off
                notchBackgroundAlwaysVisible = visibility == .always
            }
        )
    }

    private var selectedProgressTrackStyle: ProgressTrackStyle {
        ProgressTrackStyle(rawValue: progressTrackStyleRaw) ?? .softAurora
    }

    private var progressTrackAccent: Color {
        Color(
            nsColor: musicMonitor.snapshot?.bottomBackgroundColor
                ?? ArtworkPalette.fallback
        )
    }

    private var watchFaceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("表盘")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Text(selectedWatchFace.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 8),
                    count: 5
                ),
                spacing: 8
            ) {
                ForEach(WatchFaceStyle.allCases) { style in
                    watchFaceButton(style)
                }
            }

            settingToggle(
                title: "在音乐界面显示",
                detail: "关闭后音乐播放界面只保留播放内容",
                systemImage: "music.note",
                isOn: $showsWatchFaceInMusic
            )

            Divider()
                .opacity(0.5)

            HStack(spacing: 10) {
                Label("时间制式", systemImage: "clock")
                    .font(.system(size: 12, weight: .semibold))

                Spacer()

                Picker("时间制式", selection: $uses24HourClock) {
                    Text("12 小时").tag(false)
                    Text("24 小时").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 156)
            }

            if selectedWatchFace == .avatar {
                Divider()
                    .opacity(0.5)

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Label("头像 ID", systemImage: "person.crop.circle")
                            .font(.system(size: 12, weight: .semibold))

                        Spacer()

                        Button {
                            avatarSeed = "Notch-\(Int.random(in: 1000...9999))"
                        } label: {
                            Label("随机", systemImage: "shuffle")
                        }
                        .controlSize(.small)
                    }

                    TextField("输入昵称或任意文字", text: $avatarSeed)
                        .textFieldStyle(.roundedBorder)

                    Text("相同的头像 ID 会始终生成同一个头像；头像在本机离线生成。")
                        .settingsCaption()
                }
            }

            if selectedWatchFace == .emoji {
                Divider()
                    .opacity(0.5)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Emoji 表情", systemImage: "face.smiling")
                            .font(.system(size: 12, weight: .semibold))

                        Spacer()

                        Button("系统表情") {
                            openEmojiPalette()
                        }
                        .controlSize(.small)
                    }

                    TextField(
                        "输入、粘贴或从系统表情面板选择",
                        text: $watchFaceEmoji
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 15))
                    .focused($isEmojiFieldFocused)
                    .onChange(of: watchFaceEmoji) { _, value in
                        let normalized =
                            WatchFaceEmojiSettings.normalized(value)
                        if value != normalized {
                            watchFaceEmoji = normalized
                        }
                    }

                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: 6),
                            count: 8
                        ),
                        spacing: 6
                    ) {
                        ForEach(watchFaceEmojiOptions, id: \.self) { emoji in
                            emojiButton(emoji)
                        }
                    }

                    Text("可使用 macOS 系统表情面板，也可以直接输入或粘贴一个 Emoji。")
                        .settingsCaption()
                }
            }

            if selectedWatchFace == .customImage {
                Divider()
                    .opacity(0.5)

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Label("自定义图片", systemImage: "photo")
                            .font(.system(size: 12, weight: .semibold))

                        Spacer()

                        Button(
                            hasCustomWatchFaceImage ? "更换图片" : "上传图片"
                        ) {
                            chooseCustomWatchFaceImage()
                        }
                        .controlSize(.small)
                    }

                    if hasCustomWatchFaceImage {
                        HStack(spacing: 10) {
                            if let preview = customWatchFacePreview {
                                Image(nsImage: preview)
                                    .resizable()
                                    .interpolation(.high)
                                    .scaledToFill()
                                    .frame(width: 52, height: 52)
                                    .clipShape(Circle())
                                    .overlay {
                                        Circle()
                                            .strokeBorder(
                                                Color.white.opacity(0.18),
                                                lineWidth: 0.8
                                            )
                                    }
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text("已选择显示区域")
                                    .font(.system(size: 11.5, weight: .medium))

                                Text("可重新拖动选区或调整显示范围。")
                                    .settingsCaption()
                            }

                            Spacer()

                            Button("调整区域") {
                                editCustomWatchFaceImage()
                            }
                            .controlSize(.small)

                            Button {
                                removeCustomWatchFaceImage()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .controlSize(.small)
                            .help("移除自定义图片")
                            .accessibilityLabel("移除自定义图片")
                        }
                    } else {
                        Text("上传后会打开区域选择，可拖动圆形选区并调整大小。")
                            .settingsCaption()
                    }

                    if let watchFaceImageError {
                        Text(watchFaceImageError)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Color.red.opacity(0.86))
                    }

                    Text("图片仅保存在本机，不会上传。")
                        .settingsCaption()
                }
            }
        }
    }

    private func emojiButton(_ emoji: String) -> some View {
        let isSelected =
            WatchFaceEmojiSettings.normalized(watchFaceEmoji) == emoji

        return Button {
            watchFaceEmoji = emoji
        } label: {
            Text(emoji)
                .font(.system(size: 17))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .settingsSelectionCard(
                    isSelected: isSelected,
                    cornerRadius: 8,
                    selectedFillOpacity: 0.16,
                    unselectedFillOpacity: 0.045,
                    selectedBorderOpacity: 0.58,
                    selectedBorderWidth: 0.8,
                    unselectedBorderWidth: 0.8
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("表盘表情 \(emoji)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func openEmojiPalette() {
        isEmojiFieldFocused = true
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontCharacterPalette(nil)
        }
    }

    private var hasCustomWatchFaceImage: Bool {
        !watchFaceImagePath.isEmpty
            && FileManager.default.fileExists(atPath: watchFaceImagePath)
    }

    private var customWatchFacePreview: NSImage? {
        WatchFaceImageSettings.croppedImage(
            path: watchFaceImagePath,
            crop: WatchFaceImageSettings.normalizedCrop(
                watchFaceImageCropRawValue
            )
        )
    }

    private func chooseCustomWatchFaceImage() {
        watchFaceImageError = nil

        let panel = NSOpenPanel()
        panel.title = "选择表盘图片"
        panel.message = "支持 PNG、JPEG、HEIC 等常见图片格式。"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            DispatchQueue.main.async {
                guard let image = NSImage(contentsOf: url) else {
                    watchFaceImageError = "无法读取所选图片。"
                    return
                }
                watchFaceCropEditor = WatchFaceCropEditorState(
                    image: image,
                    initialCrop: WatchFaceImageSettings.centeredCrop(
                        for: image
                    ),
                    existingPath: nil
                )
            }
        }
    }

    private func editCustomWatchFaceImage() {
        guard hasCustomWatchFaceImage,
              let image = NSImage(contentsOfFile: watchFaceImagePath) else {
            watchFaceImageError = "自定义图片已丢失，请重新上传。"
            return
        }

        watchFaceImageError = nil
        watchFaceCropEditor = WatchFaceCropEditorState(
            image: image,
            initialCrop: WatchFaceImageSettings.normalizedCrop(
                watchFaceImageCropRawValue
            ),
            existingPath: watchFaceImagePath
        )
    }

    private func applyWatchFaceCrop(
        _ crop: CGRect,
        editor: WatchFaceCropEditorState
    ) {
        let encodedCrop = WatchFaceImageSettings.encodedCrop(crop)

        if editor.existingPath != nil {
            watchFaceImageCropRawValue = encodedCrop
            watchFaceImageError = nil
            return
        }

        do {
            let oldPath = watchFaceImagePath
            let newPath = try WatchFaceImageSettings.saveImage(editor.image)
            watchFaceImagePath = newPath
            watchFaceImageCropRawValue = encodedCrop
            watchFaceImageError = nil

            if !oldPath.isEmpty, oldPath != newPath {
                WatchFaceImageSettings.removeImage(at: oldPath)
            }
        } catch {
            watchFaceImageError = error.localizedDescription
        }
    }

    private func removeCustomWatchFaceImage() {
        WatchFaceImageSettings.removeImage(at: watchFaceImagePath)
        watchFaceImagePath = ""
        watchFaceImageCropRawValue = ""
        watchFaceImageError = nil
    }

    private var musicControlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader(
                    title: "媒体控制",
                    systemImage: "playpause.fill"
                )

                Spacer()

                Text("\(musicControlSlots.compactMap { $0 }.count)/\(MusicControlLayoutSettings.slotCount)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(
                        0..<MusicControlLayoutSettings.slotCount,
                        id: \.self
                    ) { index in
                        musicControlSlot(index)
                    }
                }
                .padding(7)
                .frame(maxWidth: .infinity)
                .background(
                    Color.black.opacity(
                        colorScheme == .dark ? 0.22 : 0.06
                    ),
                    in: RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            Color.primary.opacity(0.08),
                            lineWidth: 0.8
                        )
                }

                Button(action: clearSelectedMusicControlSlot) {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(
                            canClearSelectedMusicControlSlot
                                ? Color.primary.opacity(0.82)
                                : Color.secondary.opacity(0.35)
                        )
                        .frame(width: 52, height: 56)
                        .background(
                            Color.primary.opacity(0.045),
                            in: RoundedRectangle(
                                cornerRadius: 14,
                                style: .continuous
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: 14,
                                style: .continuous
                            )
                            .strokeBorder(
                                Color.primary.opacity(0.08),
                                lineWidth: 0.8
                            )
                        }
                }
                .buttonStyle(.plain)
                .disabled(!canClearSelectedMusicControlSlot)
                .help("清空选中的槽位")
                .accessibilityLabel("清空选中的槽位")
            }

            Text("在槽位之间拖动控件，或从下方面板拖入；点击槽位后可用右侧按钮清空。")
                .settingsCaption()

            Divider()
                .opacity(0.5)

            Text("控制面板")
                .font(.system(size: 12, weight: .semibold))

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 8),
                    count: MusicControlItem.allCases.count
                ),
                spacing: 8
            ) {
                ForEach(MusicControlItem.allCases) { item in
                    musicControlPaletteButton(item)
                }
            }

            HStack {
                Text("音乐频谱固定在进度条下方，可在下方单独启用。")
                    .settingsCaption()

                Spacer(minLength: 8)

                Button("恢复默认") {
                    selectedMusicControlSlot = nil
                    musicControlLayoutRaw =
                        MusicControlLayoutSettings.defaultRawValue
                }
                .controlSize(.small)
            }
        }
    }

    private var musicControlSlots: [MusicControlItem?] {
        MusicControlLayoutSettings.decode(musicControlLayoutRaw)
    }

    private var canClearSelectedMusicControlSlot: Bool {
        guard let selectedMusicControlSlot,
              musicControlSlots.indices.contains(selectedMusicControlSlot)
        else {
            return false
        }
        return musicControlSlots[selectedMusicControlSlot] != nil
    }

    private func musicControlSlot(_ index: Int) -> some View {
        let item = musicControlSlots[index]
        let isSelected = selectedMusicControlSlot == index

        return Button {
            selectedMusicControlSlot = index
        } label: {
            ZStack {
                if let item {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.86))
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .settingsSelectionCard(
                isSelected: isSelected,
                cornerRadius: 10,
                selectedFillOpacity: 0.16,
                unselectedFillOpacity: 0.045,
                selectedBorderOpacity: 0.72
            )
            .contentShape(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .draggable(item?.rawValue ?? "")
        .dropDestination(for: String.self) { payloads, _ in
            guard let rawValue = payloads.first,
                  let item = MusicControlItem(rawValue: rawValue) else {
                return false
            }
            placeMusicControl(item, in: index)
            return true
        }
        .help(item?.title ?? "空槽位")
        .accessibilityLabel(item?.title ?? "空槽位 \(index + 1)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func musicControlPaletteButton(
        _ item: MusicControlItem
    ) -> some View {
        let isPlaced = musicControlSlots.contains(item)

        return Button {
            if let existingIndex = musicControlSlots.firstIndex(of: item) {
                selectedMusicControlSlot = existingIndex
            } else if let emptyIndex = musicControlSlots.firstIndex(
                where: { $0 == nil }
            ) {
                placeMusicControl(item, in: emptyIndex)
            } else if let targetIndex = selectedMusicControlSlot {
                placeMusicControl(item, in: targetIndex)
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 16, weight: .semibold))

                Text(item.title)
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(
                isPlaced
                    ? Color.accentColor
                    : Color.primary.opacity(0.82)
            )
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                isPlaced
                    ? Color.accentColor.opacity(0.13)
                    : Color.primary.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isPlaced
                            ? Color.accentColor.opacity(0.52)
                            : Color.primary.opacity(0.08),
                        lineWidth: 0.8
                    )
            }
            .contentShape(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .draggable(item.rawValue)
        .help(item.title)
        .accessibilityLabel(item.title)
    }

    private func placeMusicControl(
        _ item: MusicControlItem,
        in targetIndex: Int
    ) {
        var slots = musicControlSlots
        guard slots.indices.contains(targetIndex) else { return }

        if let sourceIndex = slots.firstIndex(of: item) {
            guard sourceIndex != targetIndex else {
                selectedMusicControlSlot = targetIndex
                return
            }
            slots.swapAt(sourceIndex, targetIndex)
        } else {
            slots[targetIndex] = item
        }

        musicControlLayoutRaw = MusicControlLayoutSettings.encode(slots)
        selectedMusicControlSlot = targetIndex
    }

    private func clearSelectedMusicControlSlot() {
        guard let selectedMusicControlSlot else { return }
        var slots = musicControlSlots
        guard slots.indices.contains(selectedMusicControlSlot) else { return }

        slots[selectedMusicControlSlot] = nil
        musicControlLayoutRaw = MusicControlLayoutSettings.encode(slots)
    }

    private var musicSpectrumSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "音乐频谱",
                systemImage: "waveform.path.ecg"
            )

            settingToggle(
                title: "启用实时频谱",
                detail: "分析 Apple Music 音频并在灵动岛显示频谱",
                systemImage: "waveform",
                isOn: $musicSpectrumEnabled
            )

            Divider()
                .opacity(0.5)

            MusicSpectrumDetail(isEnabled: musicSpectrumEnabled)
        }
    }

    private var screenRecordingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "屏幕录制",
                systemImage: "rectangle.dashed.badge.record"
            )

            settingToggle(
                title: "启用屏幕录制检测",
                detail: "实时检测系统全局屏幕捕获状态",
                systemImage: "rectangle.inset.filled.and.person.filled",
                isOn: $screenRecordingDetectionEnabled
            )

            settingToggle(
                title: "显示录制指示器",
                detail: "录制时在灵动岛右侧显示状态图标",
                systemImage: "record.circle",
                isOn: $showsScreenRecordingIndicator
            )
            .disabled(!screenRecordingDetectionEnabled)
            .opacity(screenRecordingDetectionEnabled ? 1 : 0.48)

            Divider()
                .opacity(0.5)

            statusRow(
                title: "检测状态",
                status: screenRecordingStatusText,
                color: screenRecordingStatusColor
            )

            Text("使用事件驱动的私有 CoreGraphics 接口读取屏幕捕获状态，不访问画面内容。")
                .settingsCaption()
        }
    }

    private var focusModeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "勿扰模式",
                systemImage: "moon.fill"
            )

            settingToggle(
                title: "启用专注模式检测",
                detail: "监听系统 Focus 会话变化",
                systemImage: "moon.circle",
                isOn: $focusDetectionEnabled
            )

            settingToggle(
                title: "显示专注指示器",
                detail: "专注模式开启时在灵动岛显示状态",
                systemImage: "moon.stars",
                isOn: $showsFocusIndicator
            )
            .disabled(!focusDetectionEnabled)
            .opacity(focusDetectionEnabled ? 1 : 0.48)

            settingToggle(
                title: "显示专注标签",
                detail: "在指示器旁显示模式名称",
                systemImage: "tag",
                isOn: $showsFocusLabel
            )
            .disabled(!focusDetectionEnabled || !showsFocusIndicator)
            .opacity(
                focusDetectionEnabled && showsFocusIndicator ? 1 : 0.48
            )

            settingToggle(
                title: "以简短提示显示专注模式",
                detail: "仅显示模式名称，省略“专注”前缀",
                systemImage: "text.line.first.and.arrowtriangle.forward",
                isOn: $usesCompactFocusHint
            )
            .disabled(
                !focusDetectionEnabled
                    || !showsFocusIndicator
                    || !showsFocusLabel
            )
            .opacity(
                focusDetectionEnabled && showsFocusIndicator && showsFocusLabel
                    ? 1
                    : 0.48
            )

            Divider()
                .opacity(0.5)

            statusRow(
                title: "专注状态",
                status: focusStatusText,
                color: focusStatusColor
            )

            Text("通过分布式通知触发检测，并读取本机 Focus 会话状态；不读取通知内容。")
                .settingsCaption()
        }
    }

    private var capsLockSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "Caps Lock 指示器",
                systemImage: "capslock.fill"
            )

            settingToggle(
                title: "显示 Caps Lock 指示器",
                detail: "开启大写锁定时显示灵动岛指示器",
                systemImage: "capslock",
                isOn: $showsCapsLockIndicator
            )

            settingToggle(
                title: "显示 Caps Lock 标签",
                detail: "在图标旁显示 Caps Lock 文字",
                systemImage: "character.cursor.ibeam",
                isOn: $showsCapsLockLabel
            )
            .disabled(!showsCapsLockIndicator)
            .opacity(showsCapsLockIndicator ? 1 : 0.48)

            HStack(spacing: 10) {
                Text("Caps Lock 颜色")
                    .font(.system(size: 12, weight: .medium))

                Spacer()

                HStack(spacing: 6) {
                    ForEach(CapsLockIndicatorColor.allCases) { color in
                        capsLockColorButton(color)
                    }
                }
            }
            .disabled(!showsCapsLockIndicator)
            .opacity(showsCapsLockIndicator ? 1 : 0.48)

            Text("仅在本地读取 Caps Lock 状态，不监听或记录键盘输入。")
                .settingsCaption()
        }
    }

    private var privacyIndicatorsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "隐私指示器",
                systemImage: "hand.raised.fill"
            )

            settingToggle(
                title: "启用相机检测",
                detail: "检测相机是否正被任何应用使用",
                systemImage: "video.fill",
                isOn: $cameraDetectionEnabled
            )

            settingToggle(
                title: "启用麦克风检测",
                detail: "检测输入设备是否正被任何应用使用",
                systemImage: "mic.fill",
                isOn: $microphoneDetectionEnabled
            )

            Divider()
                .opacity(0.5)

            statusRow(
                title: "相机状态",
                status: cameraStatusText,
                color: cameraStatusColor
            )

            statusRow(
                title: "麦克风状态",
                status: microphoneStatusText,
                color: microphoneStatusColor
            )

            Text("通过 CoreMediaIO 和 CoreAudio 读取设备活动状态，不访问画面、照片或音频内容。")
                .settingsCaption()
        }
    }

    private var mouseScrollSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "鼠标滚动",
                systemImage: "computermouse.fill"
            )

            Text("平滑处理鼠标滚轮事件，并可按需翻转滚动方向。触控板保持系统原生行为。")
                .settingsCaption()

            settingToggle(
                title: "启用鼠标滚动",
                detail: "关闭后停止接管滚轮，恢复系统默认行为",
                systemImage: "power",
                isOn: $mouseScrollActive
            )

            settingToggle(
                title: "平滑滚动",
                detail: "将离散的滚轮增量转换为连续滚动",
                systemImage: "waveform.path",
                isOn: $mouseScrollSmoothingEnabled
            )
            .disabled(!mouseScrollActive)
            .opacity(mouseScrollActive ? 1 : 0.48)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("速度增益")
                        .font(.system(size: 11.5, weight: .medium))

                    Spacer()

                    Text(String(format: "%.2f", mouseScrollSpeed))
                        .font(.system(size: 11.5, weight: .semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.07), in: Capsule())
                }

                Slider(
                    value: $mouseScrollSpeed,
                    in: MouseScrollSettings.speedRange,
                    step: 0.05
                )
                .tint(.accentColor)

                HStack {
                    Text("1.0")
                    Spacer()
                    Text("10.0")
                }
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.tertiary)
            }
            .disabled(!mouseScrollActive || !mouseScrollSmoothingEnabled)
            .opacity(mouseScrollActive && mouseScrollSmoothingEnabled ? 1 : 0.48)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("持续时间")
                        .font(.system(size: 11.5, weight: .medium))

                    Spacer()

                    Text(String(format: "%.2f", mouseScrollDuration))
                        .font(.system(size: 11.5, weight: .semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.07), in: Capsule())
                }

                Slider(
                    value: $mouseScrollDuration,
                    in: MouseScrollSettings.durationRange,
                    step: 0.05
                )
                .tint(.accentColor)

                HStack {
                    Text("1.0")
                    Spacer()
                    Text("5.0")
                }
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.tertiary)
            }
            .disabled(!mouseScrollActive || !mouseScrollSmoothingEnabled)
            .opacity(mouseScrollActive && mouseScrollSmoothingEnabled ? 1 : 0.48)

            Divider()
                .opacity(0.5)

            Text("滚动方向")
                .font(.system(size: 12, weight: .medium))

            settingToggle(
                title: "翻转垂直滚动",
                detail: "交换上下滚动方向",
                systemImage: "arrow.up.arrow.down",
                isOn: $mouseScrollReverseVertical
            )
            .disabled(!mouseScrollActive)
            .opacity(mouseScrollActive ? 1 : 0.48)

            settingToggle(
                title: "翻转水平滚动",
                detail: "交换左右滚动方向",
                systemImage: "arrow.left.arrow.right",
                isOn: $mouseScrollReverseHorizontal
            )
            .disabled(!mouseScrollActive)
            .opacity(mouseScrollActive ? 1 : 0.48)

            Divider()
                .opacity(0.5)

            HStack(spacing: 8) {
                Circle()
                    .fill(mouseScrollStatus.color)
                    .frame(width: 6, height: 6)

                Text(mouseScrollStatus.text)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                if mouseScrollActive, !mouseScrollController.accessibilityGranted {
                    Button("授予权限") {
                        mouseScrollController.requestAccessibilityPermission()
                    }
                    .controlSize(.small)
                }

                Button("系统设置") {
                    mouseScrollController.openAccessibilitySettings()
                }
                .controlSize(.small)
            }

            Text("开发版重新构建后若权限失效，请在系统设置中将 NotchMusic 关闭再开启。若同时运行 Mos、LinearMouse 等滚动工具，请只保留一个接管程序。")
                .settingsCaption()
        }
    }

    private var mouseScrollStatus: (text: String, color: Color) {
        guard mouseScrollActive else {
            return ("鼠标滚动已关闭", .secondary)
        }

        let needsEventTap = mouseScrollSmoothingEnabled
            || mouseScrollReverseVertical
            || mouseScrollReverseHorizontal

        guard needsEventTap else {
            return ("滚动接管已关闭", .secondary)
        }
        guard mouseScrollController.accessibilityGranted else {
            return ("需要辅助功能权限", .orange)
        }
        guard mouseScrollController.isActive else {
            return ("未能启动，请检查权限或工具冲突", .orange)
        }
        return ("已接管鼠标滚动", .green)
    }

    private func sectionHeader(
        title: String,
        systemImage: String
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
    }

    private func settingToggle(
        title: String,
        detail: String,
        systemImage: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))

                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(.accentColor)
        }
    }

    private func statusRow(
        title: String,
        status: String,
        color: Color
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))

            Spacer()

            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text(status)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(color)
                .multilineTextAlignment(.trailing)
        }
    }

    private func capsLockColorButton(
        _ color: CapsLockIndicatorColor
    ) -> some View {
        let isSelected = color.rawValue == capsLockColorRaw

        return Button {
            capsLockColorRaw = color.rawValue
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(color.color)
                    .frame(width: 7, height: 7)

                Text(color.displayName)
                    .font(.system(size: 9.5, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                isSelected
                    ? color.color.opacity(0.18)
                    : Color.primary.opacity(0.045),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .strokeBorder(
                        isSelected
                            ? color.color.opacity(0.58)
                            : Color.primary.opacity(0.08),
                        lineWidth: 0.8
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Caps Lock 颜色 \(color.displayName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var privacyNotice: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(.secondary)

            Text("NotchMusic 通过 AppleScript 读取曲目并发送播放控制，不上传歌曲、封面或播放记录。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var aboutLinks: some View {
        VStack(spacing: 12) {
            VStack(spacing: 10) {
                HStack(spacing: 9) {
                    Text("版本 \(versionString)")

                    Divider()
                        .frame(height: 10)

                    Text("macOS 14+")
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.tertiary)

                Link(
                    destination: URL(
                        string: "https://github.com/Hoxxxxx/notch-music"
                    )!
                ) {
                    HStack(spacing: 8) {
                        Image("GitHubMark")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 13, height: 13)

                        Text("GitHub")
                            .fontWeight(.semibold)

                        Text("Hoxxxxx/notch-music")
                            .foregroundStyle(.secondary)

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .font(.system(size: 11))
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(
                        Color.primary.opacity(0.055),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                Color.primary.opacity(0.08),
                                lineWidth: 0.8
                            )
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("在 GitHub 打开 NotchMusic 仓库")
                .accessibilityLabel("GitHub 仓库 Hoxxxxx/notch-music")
            }

            Divider()
                .frame(width: 120)
                .opacity(0.65)

            Link(
                destination: URL(string: "https://www.multiavatar.com/")!
            ) {
                Text("头像样式由 Multiavatar.com 提供")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 2)
    }

    private func glassCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        return content()
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape.fill(
                    colorScheme == .dark
                        ? Color.black.opacity(0.18)
                        : Color.white.opacity(0.46)
                )
            }
            .overlay {
                shape.strokeBorder(
                    Color.white.opacity(colorScheme == .dark ? 0.10 : 0.34),
                    lineWidth: 0.8
                )
            }
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.10 : 0.04),
                radius: 8,
                y: 4
            )
    }

    private var selectedWatchFace: WatchFaceStyle {
        WatchFaceStyle(rawValue: watchFaceStyleRaw) ?? .classic
    }

    private var selectedSystemHUDStyle: SystemHUDStyle {
        SystemHUDStyle(rawValue: systemHUDStyleRaw) ?? .customOSD
    }

    private func systemHUDStyleButton(_ style: SystemHUDStyle) -> some View {
        let isSelected = style == selectedSystemHUDStyle

        return Button {
            systemHUDStyleRaw = style.rawValue
        } label: {
            VStack(spacing: 5) {
                SystemHUDPreview(style: style)
                    .frame(height: 48)

                Text(style.displayName)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .settingsSelectionCard(
                isSelected: isSelected,
                cornerRadius: 12,
                selectedFillOpacity: 0.16,
                selectedBorderOpacity: 0.72,
                selectedBorderWidth: 1,
                unselectedBorderWidth: 1
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(style.displayName)
        .accessibilityLabel("系统 HUD 样式 \(style.displayName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func stepSlider(
        title: String,
        value: Binding<Int>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))

                Spacer()

                Text("\(value.wrappedValue)%")
                    .font(.system(size: 11.5, weight: .semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.07), in: Capsule())
            }

            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0.rounded()) }
                ),
                in: 1...20,
                step: 1
            )
            .tint(.accentColor)

            HStack {
                Text("1%")
                Spacer()
                Text("20%")
            }
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(.tertiary)
        }
    }

    private var hardwareStatusText: String {
        let availability = systemHUDController.availability
        var unavailable: [String] = []
        if !availability.volume {
            unavailable.append("音量")
        }
        if !availability.displayBrightness {
            unavailable.append("内建屏亮度")
        }
        if !availability.keyboardBrightness {
            unavailable.append("键盘背光")
        }

        if unavailable.isEmpty {
            return "当前硬件接口可用。外接显示器暂不支持亮度控制。"
        }
        return "当前不可用：\(unavailable.joined(separator: "、"))。外接显示器亮度集成暂未启用。"
    }

    private func watchFaceButton(_ style: WatchFaceStyle) -> some View {
        let isSelected = style == selectedWatchFace

        return Button {
            watchFaceStyleRaw = style.rawValue
        } label: {
            VStack(spacing: 4) {
                WatchFaceView(
                    style: style,
                    accent: Color(nsColor: ArtworkPalette.fallback),
                    animatesMotion: false,
                    showsLiveTime: false
                )
                .scaleEffect(0.52)
                .frame(width: 48, height: 48)
                .clipShape(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                )

                Text(style.displayName)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .settingsSelectionCard(
                isSelected: isSelected,
                cornerRadius: 12,
                selectedFillOpacity: 0.16,
                selectedBorderOpacity: 0.72,
                selectedBorderWidth: 1,
                unselectedBorderWidth: 1
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(style.displayName)
        .accessibilityLabel("表盘 \(style.displayName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var statusText: String {
        if !musicMonitor.isConnected {
            return "尚未连接。连接后需要允许 NotchMusic 控制 Apple Music。"
        }
        if musicMonitor.needsPermission {
            return "需要自动化权限。请在系统设置中允许 NotchMusic 控制 Apple Music。"
        }
        if !musicMonitor.isMusicRunning {
            return "Apple Music 当前未运行。"
        }
        if let snapshot = musicMonitor.snapshot {
            return "正在显示：\(snapshot.title)"
        }
        return "已连接，等待 Apple Music 播放歌曲。"
    }

    private var screenRecordingStatusText: String {
        if !screenRecordingDetectionEnabled {
            return "未启用"
        }
        if !systemActivityMonitor.screenRecordingDetectionSupported {
            return "当前系统不支持"
        }
        return systemActivityMonitor.isScreenRecording
            ? "正在录制"
            : "活跃 · 未录制"
    }

    private var screenRecordingStatusColor: Color {
        guard screenRecordingDetectionEnabled,
              systemActivityMonitor.screenRecordingDetectionSupported else {
            return .secondary
        }
        return systemActivityMonitor.isScreenRecording
            ? Color(red: 0.78, green: 0.43, blue: 1.0)
            : .green
    }

    private var focusStatusText: String {
        if !focusDetectionEnabled {
            return "未启用"
        }
        guard systemActivityMonitor.isFocusActive else {
            return "活跃 · 无专注模式"
        }
        let name = systemActivityMonitor.focusName
        return name.isEmpty ? "活跃 · 专注模式" : "活跃 · \(name)"
    }

    private var focusStatusColor: Color {
        guard focusDetectionEnabled else { return .secondary }
        return systemActivityMonitor.isFocusActive
            ? Color(red: 0.67, green: 0.54, blue: 1.0)
            : .green
    }

    private var cameraStatusText: String {
        guard cameraDetectionEnabled else { return "未启用" }
        return systemActivityMonitor.isCameraActive ? "使用中" : "不活跃"
    }

    private var cameraStatusColor: Color {
        guard cameraDetectionEnabled else { return .secondary }
        return systemActivityMonitor.isCameraActive ? .orange : .green
    }

    private var microphoneStatusText: String {
        guard microphoneDetectionEnabled else { return "未启用" }
        return systemActivityMonitor.isMicrophoneActive ? "使用中" : "不活跃"
    }

    private var microphoneStatusColor: Color {
        guard microphoneDetectionEnabled else { return .secondary }
        return systemActivityMonitor.isMicrophoneActive ? .orange : .green
    }

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0"
    }
}
