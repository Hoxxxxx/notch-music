import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case lighting
    case sound
    case music
    case watchFace
    case detection
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "通用"
        case .lighting:
            return "灯光"
        case .sound:
            return "声音"
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
        case .lighting:
            return "sun.max.fill"
        case .sound:
            return "speaker.wave.2.fill"
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
        case .lighting:
            return Color(red: 1.00, green: 0.74, blue: 0.25)
        case .sound:
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

struct SettingsView: View {
    @State private var selectedCategory = SettingsCategory.general
    @State private var isSidebarExpanded = false
    @State private var hoveredCategory: SettingsCategory?
    @State private var soundIconPreviewIndex = 0
    @State private var glowPreviewLevel: CGFloat = 1
    @State private var decibelPreviewLevel: CGFloat = 0.40
    @State private var selectedMusicControlSlot: Int?
    @State private var watchFaceCropEditor: WatchFaceCropEditorState?
    @State private var watchFaceImageError: String?
    @FocusState private var isEmojiFieldFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var musicMonitor: MusicMonitor
    @EnvironmentObject private var systemActivityMonitor: SystemActivityMonitor
    @EnvironmentObject private var audioSpectrumMonitor: AudioSpectrumMonitor
    @EnvironmentObject private var systemHUDController: SystemHUDController
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
    @AppStorage(MenuBarIconStyle.storageKey)
    private var menuBarIconStyleRaw = MenuBarIconStyle.notch.rawValue
    @AppStorage(ApplicationIconStyle.storageKey)
    private var applicationIconStyleRaw = ApplicationIconStyle.ocean.rawValue

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

            settingsSidebar()
                .padding(.leading, 12)
                .frame(maxHeight: .infinity, alignment: .center)
                .zIndex(2)
        }
        .frame(width: 520, height: 720)
        .onAppear {
            musicMonitor.refreshNow()
            systemActivityMonitor.refreshNow()
            systemHUDController.refreshAvailability()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            systemHUDController.refreshAvailability()
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
                        menuBarIconSection
                    }

                    glassCard {
                        applicationIconSection
                    }

                    glassCard {
                        notchBehaviorSection
                    }

                    glassCard {
                        systemHUDStyleSection
                    }

                    glassCard {
                        systemHUDControlsSection
                    }
                }

            case .lighting:
                VStack(spacing: 12) {
                    glassCard {
                        lightingNotificationSection
                    }

                    glassCard {
                        lightingDetailsSection
                    }
                }

            case .sound:
                VStack(spacing: 12) {
                    glassCard {
                        soundNotificationSection
                    }

                    glassCard {
                        soundControlsSection
                    }
                }

            case .music:
                VStack(spacing: 12) {
                    glassCard {
                        musicSection
                    }

                    glassCard {
                        progressTrackSection
                    }

                    glassCard {
                        notchBackgroundSection
                    }

                    glassCard {
                        musicControlsSection
                    }

                    glassCard {
                        musicSpectrumSection
                    }
                }

            case .watchFace:
                glassCard {
                    watchFaceSection
                }

            case .detection:
                VStack(spacing: 12) {
                    glassCard {
                        screenRecordingSection
                    }

                    glassCard {
                        focusModeSection
                    }

                    glassCard {
                        capsLockSection
                    }

                    glassCard {
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

    private func settingsSidebar() -> some View {
        VStack(spacing: 5) {
            ForEach(SettingsCategory.allCases) { category in
                settingsSidebarButton(category)
            }
        }
        .padding(6)
        .frame(
            width: isSidebarExpanded ? 172 : 52,
            alignment: .topLeading
        )
        .settingsGlassSurface(cornerRadius: 24, interactive: true)
        .animation(
            .spring(response: 0.32, dampingFraction: 0.84),
            value: isSidebarExpanded
        )
        .onHover { hovering in
            withAnimation(
                .spring(response: 0.32, dampingFraction: 0.84)
            ) {
                isSidebarExpanded = hovering
            }
        }
    }

    private func settingsSidebarButton(
        _ category: SettingsCategory
    ) -> some View {
        let isSelected = selectedCategory == category

        return Button {
            withAnimation(
                .spring(response: 0.46, dampingFraction: 0.86)
            ) {
                selectedCategory = category
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: category.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.black : category.tint)
                    .frame(width: 26, height: 26)

                Text(category.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .frame(
                        width: isSidebarExpanded ? 100 : 0,
                        alignment: .leading
                    )
                    .opacity(isSidebarExpanded ? 1 : 0)
                    .clipped()

                Spacer(minLength: 0)
            }
            .foregroundStyle(
                isSelected
                    ? Color.black
                    : Color.white.opacity(
                        hoveredCategory == category ? 1 : 0.78
                    )
            )
            .padding(.horizontal, 7)
            .frame(
                width: isSidebarExpanded ? 160 : 40,
                height: 40,
                alignment: .leading
            )
            .background(
                Capsule()
                    .fill(
                        isSelected
                            ? Color.white
                            : hoveredCategory == category
                                ? Color.white.opacity(0.14)
                            : Color.clear
                    )
            )
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.white)
                        .shadow(
                            color: Color.white.opacity(0.55),
                            radius: 13
                        )
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                hoveredCategory = hovering ? category : nil
            }
        }
        .help(category.title)
        .accessibilityLabel(category.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                "选择系统 HUD 的布局。音量的样式、时长和反馈在“声音”中设置；亮度和键盘背光在“灯光”中设置。"
            )
                .settingsCaption()
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

    private var glowPreviewAnimation: Animation? {
        SoundHUDAppearance.animation(
            speed: selectedLightingSpeed,
            reduceMotion: reduceMotion,
            applies: true
        )
    }

    private var glowPreviewHoldDelay: UInt64 {
        switch selectedLightingSpeed {
        case .smooth:
            return 2_600_000_000
        case .fast, .instant:
            return 2_000_000_000
        }
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
                    lightingStyleButton(style)
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

            Text("HUD 布局可在“通用”中切换。")
                .settingsCaption()
        }
        .task(id: selectedLightingSpeed) {
            glowPreviewLevel = 1
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: glowPreviewHoldDelay)
                guard !Task.isCancelled else { return }
                withAnimation(glowPreviewAnimation) {
                    glowPreviewLevel = 0.64
                }
                try? await Task.sleep(nanoseconds: glowPreviewHoldDelay)
                guard !Task.isCancelled else { return }
                withAnimation(glowPreviewAnimation) {
                    glowPreviewLevel = 0.85
                }
                try? await Task.sleep(nanoseconds: glowPreviewHoldDelay)
                guard !Task.isCancelled else { return }
                withAnimation(glowPreviewAnimation) {
                    glowPreviewLevel = 1
                }
            }
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

    private var decibelPreviewAnimation: Animation? {
        SoundHUDAppearance.animation(
            speed: selectedSoundSpeed,
            reduceMotion: reduceMotion,
            applies: true
        )
    }

    private var decibelPreviewStepDelay: UInt64 {
        switch selectedSoundSpeed {
        case .smooth:
            return 800_000_000
        case .fast, .instant:
            return 450_000_000
        }
    }

    private var decibelPreviewEdgeDelay: UInt64 {
        switch selectedSoundSpeed {
        case .smooth:
            return 1_600_000_000
        case .fast, .instant:
            return 1_000_000_000
        }
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
                    soundStyleButton(style)
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

            Text("HUD 布局可在“通用”中切换。")
                .settingsCaption()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                soundIconPreviewIndex = (soundIconPreviewIndex + 1) % 3
            }
        }
        .task(id: selectedSoundSpeed) {
            let levels: [CGFloat] = [
                0.40, 0.50, 0.60, 0.70, 0.80, 0.90, 1.0
            ]
            decibelPreviewLevel = levels[0]
            while !Task.isCancelled {
                for level in levels.dropFirst() {
                    guard !Task.isCancelled else { return }
                    withAnimation(decibelPreviewAnimation) {
                        decibelPreviewLevel = level
                    }
                    try? await Task.sleep(
                        nanoseconds: decibelPreviewStepDelay
                    )
                }
                guard !Task.isCancelled else { return }
                try? await Task.sleep(
                    nanoseconds: decibelPreviewEdgeDelay
                )
                for level in levels.dropLast().reversed() {
                    guard !Task.isCancelled else { return }
                    withAnimation(decibelPreviewAnimation) {
                        decibelPreviewLevel = level
                    }
                    try? await Task.sleep(
                        nanoseconds: decibelPreviewStepDelay
                    )
                }
                guard !Task.isCancelled else { return }
                try? await Task.sleep(
                    nanoseconds: decibelPreviewEdgeDelay
                )
            }
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

    private func lightingStyleButton(_ style: LightingHUDStyle) -> some View {
        let isSelected = selectedLightingStyle == style

        return Button {
            lightingHUDStyleRaw = style.rawValue
        } label: {
            VStack(spacing: 5) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.14))

                        Capsule()
                            .fill(lightingStyleFill(style))
                            .frame(
                                width: geometry.size.width
                                    * lightingPreviewFillFraction(style)
                            )
                            .opacity(
                                style == .glow
                                    ? 0.3 + 0.7 * glowPreviewLevel
                                    : 1
                            )
                            .shadow(
                                color: lightingStyleGlow(style).opacity(
                                    style == .glow
                                        ? 0.55 + 0.45 * glowPreviewLevel
                                        : 1
                                ),
                                radius: style == .glow ? 9 : 0
                            )
                            .shadow(
                                color: style == .glow
                                    ? Color.white.opacity(
                                        0.45 + 0.4 * glowPreviewLevel
                                    )
                                    : .clear,
                                radius: 2
                            )
                    }
                    .frame(width: geometry.size.width, height: 5)
                    .position(
                        x: geometry.size.width / 2,
                        y: geometry.size.height / 2
                    )
                }
                .frame(height: 38)
                .padding(.horizontal, 13)

                Text(style.displayName)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.14)
                    : Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Color.accentColor.opacity(0.72)
                            : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 1.2 : 0.8
                    )
            }
            .contentShape(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .help(style.displayName)
        .accessibilityLabel("灯光样式 \(style.displayName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func lightingStyleFill(_ style: LightingHUDStyle) -> AnyShapeStyle {
        switch style {
        case .white:
            return AnyShapeStyle(Color.white)
        case .accent:
            return AnyShapeStyle(Color(red: 1.0, green: 0.88, blue: 0.56))
        case .glow:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.10),
                        Color.white.opacity(0.60),
                        Color.white
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
    }

    private func lightingPreviewFillFraction(
        _ style: LightingHUDStyle
    ) -> CGFloat {
        switch style {
        case .white, .accent:
            return 0.69
        case .glow:
            return glowPreviewLevel
        }
    }

    private func lightingStyleGlow(_ style: LightingHUDStyle) -> Color {
        style == .glow
            ? Color.white.opacity(0.80)
            : .clear
    }

    private func lightingSpeedButton(_ speed: SoundHUDSpeed) -> some View {
        let isSelected = selectedLightingSpeed == speed

        return Button {
            lightingHUDSpeedRaw = speed.rawValue
        } label: {
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
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.14)
                    : Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Color.accentColor.opacity(0.72)
                            : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 1.2 : 0.8
                    )
            }
            .contentShape(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .help(speed.displayName)
        .accessibilityLabel("灯光动画速度 \(speed.displayName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func soundStyleButton(_ style: SoundHUDStyle) -> some View {
        let isSelected = selectedSoundStyle == style

        return Button {
            soundHUDStyleRaw = style.rawValue
        } label: {
            VStack(spacing: 5) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.14))

                        Capsule()
                            .fill(soundStyleFill(style))
                            .frame(
                                width: geometry.size.width
                                    * soundPreviewFillFraction(style)
                            )
                            .shadow(
                                color: soundStyleGlow(style),
                                radius: style == .decibel ? 5 : 0
                            )
                    }
                    .frame(width: geometry.size.width, height: 5)
                    .position(
                        x: geometry.size.width / 2,
                        y: geometry.size.height / 2
                    )
                }
                .frame(height: 38)
                .padding(.horizontal, 13)

                Text(style.displayName)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.14)
                    : Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Color.accentColor.opacity(0.72)
                            : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 1.2 : 0.8
                    )
            }
            .contentShape(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .help(style.displayName)
        .accessibilityLabel("声音样式 \(style.displayName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func soundStyleFill(_ style: SoundHUDStyle) -> AnyShapeStyle {
        switch style {
        case .white:
            return AnyShapeStyle(Color.white)
        case .accent:
            return AnyShapeStyle(Color.accentColor)
        case .decibel:
            return AnyShapeStyle(decibelPreviewColor)
        }
    }

    private func soundStyleGlow(_ style: SoundHUDStyle) -> Color {
        style == .decibel
            ? decibelPreviewColor.opacity(0.55)
            : .clear
    }

    private var decibelPreviewColor: Color {
        SoundHUDAppearance.decibelColor(for: decibelPreviewLevel)
    }

    private func soundPreviewFillFraction(
        _ style: SoundHUDStyle
    ) -> CGFloat {
        switch style {
        case .white, .accent:
            return 0.69
        case .decibel:
            return decibelPreviewLevel
        }
    }

    private func soundSpeedButton(_ speed: SoundHUDSpeed) -> some View {
        let isSelected = selectedSoundSpeed == speed

        return Button {
            soundHUDSpeedRaw = speed.rawValue
        } label: {
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
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.14)
                    : Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Color.accentColor.opacity(0.72)
                            : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 1.2 : 0.8
                    )
            }
            .contentShape(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .help(speed.displayName)
        .accessibilityLabel("动画速度 \(speed.displayName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func soundContentButton(_ content: SoundHUDContent) -> some View {
        let isSelected = selectedSoundContent == content

        return Button {
            soundHUDContentRaw = content.rawValue
        } label: {
            soundContentIcon(content)
                .frame(height: 38)
                .padding(4)
                .frame(maxWidth: .infinity)
                .background(
                    isSelected
                        ? Color.accentColor.opacity(0.14)
                        : Color.primary.opacity(0.035),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            isSelected
                                ? Color.accentColor.opacity(0.72)
                                : Color.primary.opacity(0.08),
                            lineWidth: isSelected ? 1.2 : 0.8
                        )
                }
                .contentShape(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .help(content.displayName)
        .accessibilityLabel(content.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func soundContentIcon(_ content: SoundHUDContent) -> some View {
        if content == .symbol {
            SoundSymbolCarousel(size: 22, index: soundIconPreviewIndex)
        } else {
            SoundDeviceIconCarousel(size: 32, index: soundIconPreviewIndex)
        }
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

    private var menuBarIconSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "菜单栏图标",
                systemImage: "menubar.rectangle"
            )

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
                .background(
                    isSelected
                        ? Color.accentColor.opacity(0.14)
                        : Color.primary.opacity(0.035),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isSelected
                                ? Color.accentColor.opacity(0.62)
                                : Color.primary.opacity(0.08),
                            lineWidth: isSelected ? 1.2 : 0.8
                        )
                }
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

    private var applicationIconSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader(
                    title: "应用图标",
                    systemImage: "app.fill"
                )

                Spacer()

                Text(selectedApplicationIconStyle.displayName)
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
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.14)
                    : Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Color.accentColor.opacity(0.62)
                            : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 1.2 : 0.8
                    )
            }
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
        }
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
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.14)
                    : Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Color.accentColor.opacity(0.62)
                            : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 1.2 : 0.8
                    )
            }
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
                        isPlaying: true,
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

            settingToggle(
                title: "启用底部动态背景",
                detail: "仅在音乐播放时显示，颜色跟随专辑封面",
                systemImage: "music.note.tv",
                isOn: $notchBackgroundEnabled
            )

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

            Text("背景动画会跟随当前专辑封面主色，并在暂停播放时淡出。")
                .settingsCaption()
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
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.14)
                    : Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Color.accentColor.opacity(0.62)
                            : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 1.2 : 0.8
                    )
            }
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
                .background(
                    isSelected
                        ? Color.accentColor.opacity(0.16)
                        : Color.primary.opacity(0.045),
                    in: RoundedRectangle(
                        cornerRadius: 8,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isSelected
                                ? Color.accentColor.opacity(0.58)
                                : Color.primary.opacity(0.08),
                            lineWidth: 0.8
                        )
                }
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
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.16)
                            : Color.primary.opacity(0.045)
                    )

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
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Color.accentColor.opacity(0.72)
                            : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 1.2 : 0.8
                    )
            }
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

            statusRow(
                title: "频谱状态",
                status: audioSpectrumMonitor.status.text,
                color: musicSpectrumStatusColor
            )

            HStack(alignment: .top, spacing: 8) {
                Text("使用 Core Audio Process Tap 仅捕获 Apple Music。首次播放时系统会请求音频录制权限，频谱只在本机计算，不保存或上传音频。")
                    .settingsCaption()

                Spacer(minLength: 4)

                Button("隐私设置") {
                    audioSpectrumMonitor.openPrivacySettings()
                }
                .controlSize(.small)
                .disabled(!musicSpectrumEnabled)
            }
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
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.16)
                    : Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Color.accentColor.opacity(0.72)
                            : Color.primary.opacity(0.08),
                        lineWidth: 1
                    )
            }
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
                    accent: Color(nsColor: ArtworkPalette.fallback)
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
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.16)
                    : Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Color.accentColor.opacity(0.72)
                            : Color.primary.opacity(0.08),
                        lineWidth: 1
                    )
            }
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

    private var musicSpectrumStatusColor: Color {
        switch audioSpectrumMonitor.status {
        case .running:
            return .green
        case .starting:
            return .orange
        case .failed:
            return .red
        case .disabled, .waitingForPlayback, .unsupported:
            return .secondary
        }
    }

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0"
    }
}

private struct SparklesText: View {
    let text: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sparkles: [Sparkle] = []

    private let colors = [
        Color(red: 0.62, green: 0.48, blue: 1.00),
        Color(red: 1.00, green: 0.55, blue: 0.73)
    ]

    var body: some View {
        Text(text)
            .overlay {
                if !reduceMotion {
                    GeometryReader { geometry in
                        ForEach(sparkles) { sparkle in
                            SparkleStar(sparkle: sparkle)
                                .position(
                                    x: geometry.size.width * sparkle.x,
                                    y: geometry.size.height * sparkle.y
                                )
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .onAppear {
                guard sparkles.isEmpty else { return }
                sparkles = (0..<10).map { _ in
                    Sparkle(
                        x: .random(in: 0...1),
                        y: .random(in: 0...1),
                        color: colors.randomElement() ?? .white,
                        delay: .random(in: 0...2),
                        scale: .random(in: 0.3...1.3)
                    )
                }
            }
    }
}

private struct Sparkle: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let color: Color
    let delay: Double
    let scale: CGFloat
}

private struct SparkleStar: View {
    let sparkle: Sparkle

    @State private var isVisible = false

    var body: some View {
        SparkleShape()
            .fill(sparkle.color)
            .frame(width: 13, height: 13)
            .scaleEffect(isVisible ? sparkle.scale : 0.001)
            .opacity(isVisible ? 1 : 0)
            .rotationEffect(.degrees(isVisible ? 150 : 75))
            .animation(
                .easeInOut(duration: 0.4)
                    .repeatForever(autoreverses: true)
                    .delay(sparkle.delay),
                value: isVisible
            )
            .onAppear { isVisible = true }
    }
}

private struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scaleX = rect.width / 21
        let scaleY = rect.height / 21

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: rect.minX + x * scaleX,
                y: rect.minY + y * scaleY
            )
        }

        var path = Path()
        path.move(to: point(9.82531, 0.843845))
        path.addCurve(
            to: point(11.1746, 0.843845),
            control1: point(10.0553, 0.215178),
            control2: point(10.9446, 0.215178)
        )
        path.addLine(to: point(11.8618, 2.72026))
        path.addCurve(
            to: point(13.5, 7.5),
            control1: point(12.4006, 4.19229),
            control2: point(12.3916, 6.39157)
        )
        path.addCurve(
            to: point(18.2797, 9.13822),
            control1: point(14.6084, 8.60843),
            control2: point(16.8077, 8.59935)
        )
        path.addLine(to: point(20.1561, 9.82534))
        path.addCurve(
            to: point(20.1561, 11.1747),
            control1: point(20.7858, 10.0553),
            control2: point(20.7858, 10.9447)
        )
        path.addLine(to: point(18.2797, 11.8618))
        path.addCurve(
            to: point(13.5, 13.5),
            control1: point(16.8077, 12.4007),
            control2: point(14.6084, 12.3916)
        )
        path.addCurve(
            to: point(11.8618, 18.2798),
            control1: point(12.3916, 14.6084),
            control2: point(12.4006, 16.8077)
        )
        path.addLine(to: point(11.1746, 20.1562))
        path.addCurve(
            to: point(9.82531, 20.1562),
            control1: point(10.9446, 20.7858),
            control2: point(10.0553, 20.7858)
        )
        path.addLine(to: point(9.13819, 18.2798))
        path.addCurve(
            to: point(7.5, 13.5),
            control1: point(8.59932, 16.8077),
            control2: point(8.60843, 14.6084)
        )
        path.addCurve(
            to: point(2.72023, 11.8618),
            control1: point(6.39157, 12.3916),
            control2: point(4.19225, 12.4007)
        )
        path.addLine(to: point(0.843814, 11.1747))
        path.addCurve(
            to: point(0.843814, 9.82534),
            control1: point(0.215148, 10.9447),
            control2: point(0.215148, 10.0553)
        )
        path.addLine(to: point(2.72023, 9.13822))
        path.addCurve(
            to: point(7.5, 7.5),
            control1: point(4.19225, 8.59935),
            control2: point(6.39157, 8.60843)
        )
        path.addCurve(
            to: point(9.13819, 2.72026),
            control1: point(8.60843, 6.39157),
            control2: point(8.59932, 4.19229)
        )
        path.closeSubpath()
        return path
    }
}

private struct ConfettiLayer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            ConfettiCanvas(time: 0, frozen: true)
        } else {
            TimelineView(.animation) { timeline in
                ConfettiCanvas(
                    time: timeline.date.timeIntervalSinceReferenceDate,
                    frozen: false
                )
            }
        }
    }
}

private struct ConfettiCanvas: View {
    let time: TimeInterval
    let frozen: Bool

    private let particleCount = 44

    private let palette = [
        Color(red: 1.00, green: 0.42, blue: 0.34),
        Color(red: 1.00, green: 0.55, blue: 0.73),
        Color(red: 0.62, green: 0.48, blue: 1.00),
        Color(red: 1.00, green: 0.80, blue: 0.45),
        Color(red: 0.45, green: 0.80, blue: 0.70),
        Color(red: 0.42, green: 0.80, blue: 0.62)
    ]

    var body: some View {
        Canvas { context, size in
            guard size.width > 120 else { return }
            for index in 0..<particleCount {
                drawFlake(in: &context, size: size, index: index)
            }
        }
    }

    private func drawFlake(
        in context: inout GraphicsContext,
        size: CGSize,
        index: Int
    ) {
        let seed = Double(unitRandom(index, 1))
        let startX =
            Double(size.width) * (0.05 + 0.9 * Double(unitRandom(index, 2)))
        let startY = 50 + 45 * Double(unitRandom(index, 3))
        let entrySpeed = 70 * Double(unitRandom(index, 4))
        let terminalSpeed = 140 + 100 * Double(unitRandom(index, 5))
        let drag = 2.5 + 2.5 * Double(unitRandom(index, 6))
        let swaySpeed = 0.7 + 1.7 * Double(unitRandom(index, 7))
        let swayAmplitude = 7 + 20 * Double(unitRandom(index, 8))
        let restDuration = 1.2 + 1.6 * Double(unitRandom(index, 9))
        let gapDuration = 0.15 + 0.9 * Double(unitRandom(index, 10))
        let floorY =
            Double(size.height) - 14 - 40 * Double(unitRandom(index, 11))
        let baseRotation = 360 * Double(unitRandom(index, 12))
        let driftSpeed = (Double(unitRandom(index, 13)) - 0.5) * 80
        let tumbleSpeed = 1.2 + 3.0 * Double(unitRandom(index, 14))
        let tumbleAmplitude = 20 + 150 * Double(unitRandom(index, 15))
        let flipSpeed = 1.5 + 4.0 * Double(unitRandom(index, 16))
        let flipPhase = 6.28 * Double(unitRandom(index, 17))
        let driftDirection = Double(unitRandom(index, 18)) - 0.5

        func fallY(at moment: Double) -> Double {
            startY + terminalSpeed * moment
                + (entrySpeed - terminalSpeed) * (1 - exp(-drag * moment))
                    / drag
        }

        var low = 0.0
        var high = 10.0
        for _ in 0..<28 {
            let mid = (low + high) / 2
            if fallY(at: mid) < floorY {
                low = mid
            } else {
                high = mid
            }
        }
        let landingTime = (low + high) / 2
        let period = landingTime + restDuration + gapDuration
        let phase = period * Double(unitRandom(index, 19))
        let elapsed = frozen
            ? landingTime * (0.2 + 0.6 * Double(unitRandom(index, 20)))
            : (time + phase).truncatingRemainder(dividingBy: period)
        guard elapsed < landingTime + restDuration else { return }

        func sway(at moment: Double) -> Double {
            let primary =
                sin(moment * swaySpeed * 2 * .pi + seed * 6.28)
                * swayAmplitude
            let secondary =
                sin(moment * swaySpeed * 3.6 * .pi + seed * 3.1)
                * swayAmplitude * 0.3
            return (primary + secondary) * min(1, moment / 1.2)
        }

        func rotation(at moment: Double) -> Double {
            baseRotation + driftSpeed * moment
                + sin(moment * tumbleSpeed + seed * 6.28) * tumbleAmplitude
        }

        func paperFlip(at moment: Double) -> Double {
            0.12 + 0.88 * abs(cos(moment * flipSpeed + flipPhase))
        }

        let x: Double
        let y: Double
        let flakeRotation: Double
        let flakeFlip: Double
        let opacity: Double

        if elapsed < landingTime {
            y = fallY(at: elapsed)
            x =
                startX + sway(at: elapsed)
                + driftDirection * 24 * elapsed
            flakeRotation = rotation(at: elapsed)
            flakeFlip = paperFlip(at: elapsed)
            opacity = min(1, elapsed / 0.35)
        } else {
            let restTime = elapsed - landingTime
            let fadeStart = restDuration * 0.55
            let bounce =
                max(0, sin(restTime * 10)) * 2.5 * exp(-restTime * 6)
            x =
                startX + sway(at: landingTime)
                + driftDirection * 24 * landingTime
            y = floorY - bounce
            flakeRotation = rotation(at: landingTime)
            flakeFlip = 1
            if restTime < fadeStart {
                opacity = 1
            } else {
                let fadeProgress =
                    (restTime - fadeStart) / (restDuration - fadeStart)
                opacity =
                    1 - Double(smoothstep(0, 1, CGFloat(fadeProgress)))
            }
        }

        guard opacity > 0.01 else { return }

        let color = palette[index % palette.count]
        let width = 4 + 3 * unitRandom(index, 21)
        let height = 7 + 7 * unitRandom(index, 22)

        var particle = context
        particle.translateBy(x: CGFloat(x), y: CGFloat(y))
        particle.rotate(by: .degrees(flakeRotation))
        var flake = particle
        flake.scaleBy(x: 1, y: CGFloat(flakeFlip))
        flake.fill(
            Path(
                roundedRect: CGRect(
                    x: -width / 2,
                    y: -height / 2,
                    width: width,
                    height: height
                ),
                cornerRadius: 1.2
            ),
            with: .color(color.opacity(opacity))
        )
    }

    private func unitRandom(_ index: Int, _ salt: Int) -> CGFloat {
        let value =
            sin(Double(index) * 12.9898 + Double(salt) * 78.233)
            * 43758.5453
        return CGFloat(value - floor(value))
    }

    private func smoothstep(
        _ edge0: CGFloat,
        _ edge1: CGFloat,
        _ value: CGFloat
    ) -> CGFloat {
        let t = min(max((value - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

private struct SoundDeviceIconCarousel: View {
    let size: CGFloat
    let index: Int

    private var models: [AirPodsModelKind] {
        let allModels: [AirPodsModelKind] = [
            .airPods,
            .airPodsPro,
            .airPodsMax
        ]
        guard let preferred = SoundOutputDevice.preferredAirPodsModel(),
              allModels.contains(preferred) else {
            return allModels
        }
        return [preferred] + allModels.filter { $0 != preferred }
    }

    var body: some View {
        ZStack {
            if !models.isEmpty {
                let model = models[index % models.count]
                AirPods3DView(model: model)
                    .id(model)
                    .frame(width: size, height: size)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.74, anchor: .center)
                                .combined(with: .opacity),
                            removal: .scale(scale: 0.86, anchor: .center)
                                .combined(with: .opacity)
                        )
                    )
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .animation(
            .spring(
                response: 0.9,
                dampingFraction: 0.82,
                blendDuration: 0
            ),
            value: index
        )
    }
}

private struct SoundSymbolCarousel: View {
    let size: CGFloat
    let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedIndex = 0
    @State private var isCollapsed = false

    private var symbols: [String] {
        let models: [AirPodsModelKind] = [
            .airPods,
            .airPodsPro,
            .airPodsMax
        ]
        let preferred = SoundOutputDevice.preferredAirPodsModel()
        let ordered = preferred.map { first in
            [first] + models.filter { $0 != first }
        } ?? models
        return ordered.map(\.systemImage)
    }

    var body: some View {
        Image(systemName: symbols[displayedIndex % symbols.count])
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(.white)
            .scaleEffect(isCollapsed ? 0.01 : 1)
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
            .onAppear {
                displayedIndex = index
            }
            .onChange(of: index) { _, newIndex in
                guard !reduceMotion else {
                    displayedIndex = newIndex
                    return
                }
                withAnimation(.easeIn(duration: 0.18)) {
                    isCollapsed = true
                }
                Task {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    displayedIndex = newIndex
                    withAnimation(.easeOut(duration: 0.24)) {
                        isCollapsed = false
                    }
                }
            }
    }

}

private struct WatchFaceCropEditorState: Identifiable {
    let id = UUID()
    let image: NSImage
    let initialCrop: CGRect
    let existingPath: String?
}

private struct WatchFaceCropEditor: View {
    let image: NSImage
    let onCancel: () -> Void
    let onConfirm: (CGRect) -> Void

    @State private var cropRect: CGRect
    @State private var sizeFraction: Double
    @State private var moveStartRect: CGRect?

    init(
        image: NSImage,
        initialCrop: CGRect,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (CGRect) -> Void
    ) {
        self.image = image
        self.onCancel = onCancel
        self.onConfirm = onConfirm

        let fallback = WatchFaceImageSettings.centeredCrop(for: image)
        let displayWidth = initialCrop.width * image.size.width
        let displayHeight = initialCrop.height * image.size.height
        let isUsable = initialCrop.width > 0
            && initialCrop.height > 0
            && displayHeight > 0
            && abs(displayWidth / displayHeight - 1) < 0.02
        let resolvedCrop = isUsable ? initialCrop : fallback
        let maximumSquare = max(
            min(image.size.width, image.size.height),
            1
        )
        let selectedSquare = min(displayWidth, displayHeight)
        let initialFraction = resolvedCrop == fallback
            ? 0.78
            : Double(selectedSquare / maximumSquare)

        _cropRect = State(initialValue: resolvedCrop)
        _sizeFraction = State(
            initialValue: min(max(initialFraction, 0.2), 1)
        )
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("选择表盘区域")
                        .font(.system(size: 17, weight: .semibold))

                    Text("拖动圆角选区调整位置，使用滑块调整显示范围。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .background(
                    Color.primary.opacity(0.06),
                    in: Circle()
                )
                .accessibilityLabel("关闭区域选择")
            }

            GeometryReader { geometry in
                let canvasHeight = max(geometry.size.height - 38, 1)
                let canvasSize = CGSize(
                    width: geometry.size.width,
                    height: canvasHeight
                )
                let imageRect = aspectFitRect(
                    imageSize: image.size,
                    in: CGRect(origin: .zero, size: canvasSize)
                        .insetBy(dx: 10, dy: 0)
                )

                VStack(spacing: 10) {
                    imageCanvas(
                        imageRect: imageRect,
                        canvasSize: canvasSize
                    )
                    .frame(height: canvasHeight)

                    HStack(spacing: 10) {
                        Image(systemName: "rectangle.dashed")
                            .foregroundStyle(.secondary)

                        Slider(
                            value: sizeBinding(imageRect: imageRect),
                            in: 0.2...1
                        )

                        Text("\(Int((sizeFraction * 100).rounded()))%")
                            .font(.system(size: 10.5, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                    .frame(height: 28)
                }
            }
            .frame(height: 408)

            HStack(spacing: 10) {
                Text("选区之外的画面不会显示在表盘上。")
                    .settingsCaption()

                Spacer()

                Button("取消") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("使用此区域") {
                    onConfirm(cropRect)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 560, height: 560)
    }

    private func imageCanvas(
        imageRect: CGRect,
        canvasSize: CGSize
    ) -> some View {
        let selection = selectionRect(in: imageRect)
        let cornerRadius = selection.width
            * WatchFaceSurfaceMetrics.cornerRadiusRatio
        let selectionShape = RoundedRectangle(
            cornerRadius: cornerRadius,
            style: .continuous
        )

        return ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.34))

            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: imageRect.width, height: imageRect.height)
                .position(x: imageRect.midX, y: imageRect.midY)

            Path { path in
                path.addRect(CGRect(origin: .zero, size: canvasSize))
                path.addPath(
                    Path(
                        roundedRect: selection,
                        cornerRadius: cornerRadius
                    )
                )
            }
            .fill(
                Color.black.opacity(0.58),
                style: FillStyle(eoFill: true)
            )

            selectionShape
                .stroke(Color.white.opacity(0.96), lineWidth: 2)
                .frame(width: selection.width, height: selection.height)
                .position(x: selection.midX, y: selection.midY)
                .shadow(color: .black.opacity(0.54), radius: 3)

            RoundedRectangle(
                cornerRadius: max(
                    cornerRadius - 2.5 * WatchFaceSurfaceMetrics.cornerRadiusRatio,
                    0
                ),
                style: .continuous
            )
                .stroke(Color.accentColor.opacity(0.88), lineWidth: 1)
                .frame(
                    width: max(selection.width - 5, 1),
                    height: max(selection.height - 5, 1)
                )
                .position(x: selection.midX, y: selection.midY)

            selectionShape
                .fill(Color.clear)
                .contentShape(selectionShape)
                .frame(width: selection.width, height: selection.height)
                .position(x: selection.midX, y: selection.midY)
                .gesture(moveGesture(imageRect: imageRect))
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func moveGesture(imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard imageRect.width > 0, imageRect.height > 0 else {
                    return
                }
                if moveStartRect == nil {
                    moveStartRect = cropRect
                }
                guard let start = moveStartRect else { return }

                let deltaX = value.translation.width / imageRect.width
                let deltaY = value.translation.height / imageRect.height
                let x = min(
                    max(start.minX + deltaX, 0),
                    max(1 - start.width, 0)
                )
                let y = min(
                    max(start.minY + deltaY, 0),
                    max(1 - start.height, 0)
                )
                cropRect = CGRect(
                    x: x,
                    y: y,
                    width: start.width,
                    height: start.height
                )
            }
            .onEnded { _ in
                moveStartRect = nil
            }
    }

    private func sizeBinding(imageRect: CGRect) -> Binding<Double> {
        Binding(
            get: { sizeFraction },
            set: { newValue in
                guard imageRect.width > 0, imageRect.height > 0 else {
                    return
                }
                sizeFraction = min(max(newValue, 0.2), 1)
                let side = min(imageRect.width, imageRect.height)
                    * CGFloat(sizeFraction)
                let width = side / imageRect.width
                let height = side / imageRect.height
                let x = min(
                    max(cropRect.midX - width / 2, 0),
                    max(1 - width, 0)
                )
                let y = min(
                    max(cropRect.midY - height / 2, 0),
                    max(1 - height, 0)
                )
                cropRect = CGRect(
                    x: x,
                    y: y,
                    width: width,
                    height: height
                )
            }
        )
    }

    private func selectionRect(in imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + cropRect.minX * imageRect.width,
            y: imageRect.minY + cropRect.minY * imageRect.height,
            width: cropRect.width * imageRect.width,
            height: cropRect.height * imageRect.height
        )
    }

    private func aspectFitRect(
        imageSize: CGSize,
        in bounds: CGRect
    ) -> CGRect {
        guard imageSize.width > 0,
              imageSize.height > 0,
              bounds.width > 0,
              bounds.height > 0 else {
            return bounds
        }

        let scale = min(
            bounds.width / imageSize.width,
            bounds.height / imageSize.height
        )
        let size = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

private struct SettingsBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            SettingsWindowGlassBackground()

            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.13, green: 0.10, blue: 0.09),
                        Color(red: 0.055, green: 0.065, blue: 0.08)
                    ]
                    : [
                        Color(red: 0.97, green: 0.95, blue: 0.92),
                        Color(red: 0.86, green: 0.90, blue: 0.92)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(colorScheme == .dark ? 0.10 : 0.08)

            Circle()
                .fill(Color(red: 1.0, green: 0.36, blue: 0.25).opacity(0.18))
                .frame(width: 330, height: 330)
                .blur(radius: 72)
                .offset(x: -170, y: -150)

            Circle()
                .fill(Color(red: 0.26, green: 0.66, blue: 0.78).opacity(0.14))
                .frame(width: 300, height: 300)
                .blur(radius: 84)
                .offset(x: 185, y: 145)

            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.04 : 0.16),
                    .clear,
                    Color.black.opacity(colorScheme == .dark ? 0.06 : 0.02)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

private struct SettingsWindowGlassBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    var body: some View {
        if reduceTransparency {
            Rectangle()
                .fill(.background)
        } else if #available(macOS 26.0, *) {
            Rectangle()
                .fill(.clear)
                .glassEffect(.regular, in: Rectangle())
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Rectangle()
                        .fill(Color.white.opacity(colorScheme == .dark ? 0.035 : 0.16))
                }
        }
    }
}

private struct SystemHUDPreview: View {
    let style: SystemHUDStyle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var level = 0.34

    private var percentage: Int {
        Int((level * 100).rounded())
    }

    private var symbolName: String {
        if level < 0.34 {
            return "speaker.wave.1.fill"
        }
        if level < 0.67 {
            return "speaker.wave.2.fill"
        }
        return "speaker.wave.3.fill"
    }

    var body: some View {
        ZStack {
            switch style {
            case .island:
                island
            case .customOSD:
                customOSD
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: reduceMotion) {
            guard !reduceMotion else { return }
            let levels: [Double] = [0.34, 0.58, 0.82, 0.66, 0.95, 0.42]
            while !Task.isCancelled {
                for value in levels {
                    guard !Task.isCancelled else { return }
                    withAnimation(
                        .spring(response: 0.32, dampingFraction: 0.84)
                    ) {
                        level = value
                    }
                    try? await Task.sleep(nanoseconds: 900_000_000)
                }
            }
        }
    }

    private var island: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: symbolName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 14, alignment: .leading)
                    .transaction { $0.animation = nil }

                Text("音量")
                    .font(
                        .system(
                            size: 7,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white.opacity(0.92))
            }

            Spacer(minLength: 10)

            HStack(spacing: 4) {
                levelBar(height: 3)
                    .frame(width: 34)

                Text("\(percentage)")
                    .font(
                        .system(
                            size: 7,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .frame(width: 13, alignment: .trailing)
            }
        }
        .padding(.horizontal, 9)
        .frame(width: 170, height: 22)
        .background(
            Color.black.opacity(0.92),
            in: UnevenRoundedRectangle(
                topLeadingRadius: 7,
                bottomLeadingRadius: 13,
                bottomTrailingRadius: 13,
                topTrailingRadius: 7,
                style: .continuous
            )
        )
    }

    private var customOSD: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30, alignment: .leading)
                .transaction { $0.animation = nil }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 3) {
                    Text("音量")
                        .font(
                            .system(
                                size: 8,
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(.white)

                    Spacer(minLength: 0)

                    Text("\(percentage)%")
                        .font(
                            .system(
                                size: 9,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }

                levelBar(height: 4.5)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 9)
        .frame(width: 108, height: 48)
        .background(
            Color.black.opacity(0.86),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private func levelBar(height: CGFloat) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.22))

                Capsule()
                    .fill(.white.opacity(0.9))
                    .frame(
                        width: max(
                            height,
                            proxy.size.width * level
                        )
                    )
            }
        }
        .frame(height: height)
    }
}

private struct SettingsGlassSurface: ViewModifier {
    let cornerRadius: CGFloat
    let interactive: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var border: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.34 : 0.72),
                Color.white.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(.background, in: shape)
                .overlay {
                    shape.strokeBorder(border, lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
        } else if #available(macOS 26.0, *) {
            let glass = interactive ? Glass.regular.interactive() : Glass.regular

            content
                .glassEffect(glass, in: shape)
                .overlay {
                    shape.strokeBorder(border, lineWidth: 0.8)
                }
                .shadow(
                    color: .black.opacity(colorScheme == .dark ? 0.28 : 0.14),
                    radius: 18,
                    y: 9
                )
        } else {
            content
                .background {
                    shape
                        .fill(.ultraThinMaterial)
                        .overlay {
                            shape.fill(
                                Color.white.opacity(
                                    colorScheme == .dark ? 0.035 : 0.16
                                )
                            )
                        }
                }
                .overlay {
                    shape.strokeBorder(border, lineWidth: 0.8)
                }
                .shadow(
                    color: .black.opacity(colorScheme == .dark ? 0.24 : 0.12),
                    radius: 16,
                    y: 8
                )
        }
    }
}

private extension View {
    func settingsGlassSurface(
        cornerRadius: CGFloat,
        interactive: Bool = false
    ) -> some View {
        modifier(
            SettingsGlassSurface(
                cornerRadius: cornerRadius,
                interactive: interactive
            )
        )
    }

    func settingsCaption() -> some View {
        font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
