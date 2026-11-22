import AppKit
import SwiftUI

struct VolumeIslandView: View {
    @ObservedObject var controller: SystemHUDController
    @ObservedObject var mixer: AppVolumeMixer
    let accent: Color
    let width: CGFloat

    @AppStorage(SoundHUDSettings.speed)
    private var soundSpeedRaw = SoundHUDSpeed.smooth.rawValue
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @State private var level: Double = 0
    @State private var isMuted = false
    @State private var isDragging = false
    @State private var deviceName = ""
    @State private var isAvailable = true

    private let appRowHeight = NotchLayout.volumeRowHeight
    private let appRowSpacing = NotchLayout.volumeRowSpacing
    private let appIconSize: CGFloat = 37
    private let titleRowHeight: CGFloat = 15
    private let sliderRowHeight: CGFloat = 15

    init(
        controller: SystemHUDController,
        mixer: AppVolumeMixer,
        accent: Color,
        width: CGFloat
    ) {
        self.controller = controller
        self.mixer = mixer
        self.accent = accent
        self.width = width

        let state = controller.volumeState
        _level = State(initialValue: state?.level ?? 0)
        _isMuted = State(initialValue: state?.isMuted ?? false)
        _deviceName = State(
            initialValue: controller.volumeOutputDeviceName ?? ""
        )
        _isAvailable = State(initialValue: state != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NotchLayout.volumeDividerGap) {
            outputHeader

            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(height: 1)
                .offset(y: 2)

            appList

            if mixer.tapFailed {
                permissionHint
            }
        }
        .frame(
            width: width,
            height: NotchLayout.volumeExpandedHeight(
                appCount: mixer.apps.count,
                showsPermissionHint: mixer.tapFailed
            )
                - NotchLayout.expandedTopPadding
                - NotchLayout.volumeBottomPadding,
            alignment: .topLeading
        )
        .task { await pollVolume() }
        .onChange(of: controller.volumeReading) { _, reading in
            guard !isDragging, let reading else { return }
            isAvailable = true
            isMuted = reading.isMuted
            if abs(level - reading.level) > 0.0001 {
                level = reading.level
            }
        }
        .environment(\.controlActiveState, .active)
    }

    private var outputHeader: some View {
        let percentage = Int((level * 100).rounded())

        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.08))
                .frame(width: appIconSize, height: appIconSize)
                .overlay {
                    Image(
                        systemName: isMuted
                            ? "speaker.slash.fill"
                            : "speaker.wave.2.fill"
                    )
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(
                        isMuted ? accent : Color.white.opacity(0.82)
                    )
                }

            VStack(spacing: 4) {
                Text(currentOutputName)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(
                        isMuted
                            ? accent.opacity(0.75)
                            : Color.white.opacity(0.9)
                    )
                    .lineLimit(1)
                    .frame(height: titleRowHeight)

                if isAvailable {
                    GlassVolumeSlider(
                        value: Binding(
                            get: { level },
                            set: { newValue in
                                level = newValue
                                controller.setVolumeLevel(newValue)
                            }
                        ),
                        tint: .accentColor,
                        accessibilityLabel: "输出音量",
                        onEditingChanged: { editing in
                            isDragging = editing
                            if !editing {
                                refresh()
                            }
                        }
                    )
                    .opacity(isMuted ? 0.5 : 1)
                } else {
                    Text("当前输出设备不支持音量控制。")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: appIconSize)

            Spacer(minLength: 0)

            rowTrailing(percentage: percentage, isMuted: isMuted) {
                HStack(spacing: 6) {
                    Button {
                        controller.toggleVolumeMute()
                        refresh()
                    } label: {
                        Image(
                            systemName: isMuted
                                ? "speaker.slash.fill"
                                : "speaker.wave.2.fill"
                        )
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(
                            isMuted
                                ? accent
                                : Color.white.opacity(0.68)
                        )
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        isMuted ? "取消静音" : "静音"
                    )

                    systemOutputMenu

                    Button {
                        controller.setVolumeLevel(1)
                        refresh()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(
                                Color.red.opacity(
                                    level < 0.995 ? 0.95 : 0.78
                                )
                            )
                            .frame(width: 24, height: 24)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(level >= 0.995)
                    .accessibilityLabel("重置为 100%")
                }
                .frame(width: 84)
                .layoutPriority(1)
                .fixedSize(horizontal: true, vertical: true)
                .geometryGroup()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: appRowHeight)
    }

    private var currentOutputName: String {
        if let device = mixer.outputDevices.first(where: { $0.isDefault }) {
            return device.name
        }
        return deviceName.isEmpty ? "输出音量" : deviceName
    }

    private var systemOutputMenu: some View {
        Menu {
            ForEach(
                mixer.outputDevices.filter(\.canBeDefaultOutput)
            ) { device in
                Button {
                    mixer.setSystemOutputDevice(device.uid)
                } label: {
                    if device.isDefault {
                        Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
        } label: {
            Color.clear
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 24, height: 24)
        .opacity(0.01)
        .overlay {
            ZStack {
                Image(systemName: "airplayaudio")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.68))
            }
            .frame(width: 24, height: 24)
            .allowsHitTesting(false)
        }
        .transaction { transaction in
            transaction.animation = nil
        }
        .accessibilityLabel("输出设备")
        .help("切换系统输出设备")
    }

    private var appList: some View {
        Group {
            if mixer.apps.isEmpty {
                VStack(spacing: 5) {
                    Image(systemName: "waveform")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.16))

                    Text("没有可控制的 App")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))

                    Text("打开会播放声音的 App 后会显示在这里")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.26))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: appRowSpacing) {
                        ForEach(mixer.apps) { app in
                            appRow(app)
                        }
                    }
                }
                .frame(height: appListHeight)
                .defaultScrollAnchor(.top)
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .top
        )
    }

    private var appListHeight: CGFloat {
        NotchLayout.volumeListHeight(appCount: mixer.apps.count)
    }

    private func appRow(_ app: AppVolumeMixer.AppRow) -> some View {
        let percentage = Int((app.volume * 100).rounded())

        return HStack(spacing: 10) {
            Group {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(
                            width: appIconSize,
                            height: appIconSize
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.12))
                        .frame(
                            width: appIconSize,
                            height: appIconSize
                        )
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if app.isPlaying {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                        .overlay(
                            Circle()
                                .stroke(
                                    Color.black.opacity(0.45),
                                    lineWidth: 0.5
                                )
                        )
                        .offset(x: 2, y: 2)
                }
            }

            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Text(app.name)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(
                            app.isPlaying
                                ? Color.white.opacity(0.9)
                                : Color.white.opacity(0.62)
                        )
                        .lineLimit(1)
                        .frame(height: titleRowHeight)
                }

                GlassVolumeSlider(
                    value: Binding(
                        get: { app.volume },
                        set: { newValue in
                            mixer.setVolume(newValue, for: app.id)
                        }
                    ),
                    tint: .accentColor,
                    accessibilityLabel: app.name
                )
                .opacity(app.isMuted ? 0.5 : 1)
            }
            .frame(height: appIconSize)

            Spacer(minLength: 0)

            rowTrailing(percentage: percentage, isMuted: app.isMuted) {
                HStack(spacing: 6) {
                    Button {
                        mixer.toggleMute(for: app.id)
                    } label: {
                        Image(
                            systemName: app.isMuted
                                ? "speaker.slash.fill"
                                : "speaker.wave.2.fill"
                        )
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(
                            app.isMuted
                                ? accent
                                : Color.white.opacity(0.68)
                        )
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        app.isMuted ? "取消静音" : "静音"
                    )

                    appOutputMenu(for: app)

                    Button {
                        mixer.setVolume(1, for: app.id)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(
                                Color.red.opacity(
                                    app.volume < 0.995 ? 0.95 : 0.78
                                )
                            )
                            .frame(width: 24, height: 24)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(app.volume >= 0.995)
                    .accessibilityLabel("重置为 100%")
                }
                .frame(width: 84)
                .layoutPriority(1)
                .fixedSize(horizontal: true, vertical: true)
                .geometryGroup()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: appRowHeight)
    }

    private func rowTrailing<Buttons: View>(
        percentage: Int,
        isMuted: Bool,
        @ViewBuilder buttons: () -> Buttons
    ) -> some View {
        VStack(spacing: 4) {
            Color.clear
                .frame(height: titleRowHeight)

            HStack(spacing: 10) {
                Text("\(percentage)%")
                    .font(
                        .system(
                            size: 11,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                    .foregroundStyle(
                        isMuted
                            ? accent.opacity(0.9)
                            : Color.white.opacity(0.74)
                    )
                    .contentTransition(
                        .numericText()
                    )
                    .animation(
                        SoundHUDAppearance.animation(
                            speed: SoundHUDSpeed(
                                rawValue: soundSpeedRaw
                            ) ?? .smooth,
                            reduceMotion: reduceMotion,
                            applies: true
                        ),
                        value: percentage
                    )
                    .frame(width: 36, alignment: .trailing)

                buttons()
            }
            .frame(height: sliderRowHeight)
        }
        .frame(height: appIconSize)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func appOutputMenu(
        for app: AppVolumeMixer.AppRow
    ) -> some View {
        Menu {
            Button {
                mixer.setOutputDevice(nil, for: app.id)
            } label: {
                if app.outputDeviceUID == nil {
                    Label("跟随系统", systemImage: "checkmark")
                } else {
                    Text("跟随系统")
                }
            }

            Divider()

            ForEach(mixer.outputDevices) { device in
                Button {
                    mixer.setOutputDevice(device.uid, for: app.id)
                } label: {
                    if app.outputDeviceUID == device.uid {
                        Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
        } label: {
            Color.clear
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 24, height: 24)
        .opacity(0.01)
        .overlay {
            ZStack {
                Image(systemName: "airplayaudio")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(
                        app.outputDeviceUID == nil
                            ? Color.white.opacity(0.68)
                            : Color.accentColor
                    )
            }
            .frame(width: 24, height: 24)
            .allowsHitTesting(false)
        }
        .transaction { transaction in
            transaction.animation = nil
        }
        .accessibilityLabel("输出设备")
        .help("输出设备：\(appOutputName(for: app))")
    }

    private func appOutputName(
        for app: AppVolumeMixer.AppRow
    ) -> String {
        if let uid = app.outputDeviceUID,
           let device = mixer.outputDevices.first(
               where: { $0.uid == uid }
           ) {
            return device.name
        }
        if app.outputDeviceUnavailable {
            return "所选设备不可用，跟随系统"
        }
        return "跟随系统（\(currentOutputName)）"
    }

    private var permissionHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Color.orange.opacity(0.9))

            Text("需要“屏幕与系统音频录制”权限")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.52))
                .lineLimit(1)

            Spacer(minLength: 4)

            Button("打开设置") {
                mixer.openAudioPermissionSettings()
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(accent)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.06))
        )
    }

    private func pollVolume() async {
        refresh()

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            if !isDragging {
                refresh()
            }
        }
    }

    private func refresh() {
        guard let state = controller.volumeState else {
            isAvailable = false
            return
        }

        isAvailable = true
        isMuted = state.isMuted
        deviceName = controller.volumeOutputDeviceName ?? ""

        if !isDragging, abs(level - state.level) > 0.005 {
            level = state.level
        }
    }
}

private struct GlassVolumeSlider: View {
    @Binding var value: Double
    let tint: Color
    let accessibilityLabel: String
    var onEditingChanged: (Bool) -> Void = { _ in }

    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @State private var isDragging = false

    private let knobWidth: CGFloat = 24
    private let knobHeight: CGFloat = 15
    private let trackHeight: CGFloat = 5
    private let leadingInset: CGFloat = 5
    private let trailingBleed: CGFloat = -1

    private var progress: CGFloat {
        CGFloat(min(max(value, 0), 1))
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(
                proxy.size.width - leadingInset + trailingBleed,
                knobWidth
            )
            let amount = progress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(trackOpacity))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(tint)
                    .frame(
                        width: fillWidth(width: width, amount: amount),
                        height: trackHeight
                    )
                    .shadow(color: tint.opacity(0.18), radius: 3)

                knob(width: width, amount: amount)
                    .frame(width: knobWidth, height: knobHeight)
                    .offset(x: width * amount - knobWidth / 2)
            }
            .frame(
                width: width,
                height: knobHeight
            )
            .offset(x: leadingInset)
            .frame(
                width: proxy.size.width,
                height: proxy.size.height,
                alignment: .leading
            )
            .animation(.easeOut(duration: 0.16), value: amount)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        updateValue(
                            at: gesture.location.x - leadingInset,
                            width: width
                        )
                    }
                    .onEnded { _ in
                        guard isDragging else { return }
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: knobHeight)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(
            "\(Int((progress * 100).rounded()))%"
        )
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = min(1, value + 0.05)
            case .decrement:
                value = max(0, value - 0.05)
            @unknown default:
                break
            }
        }
    }

    private var trackOpacity: Double {
        colorScheme == .light ? 0.11 : 0.16
    }

    private func fillWidth(width: CGFloat, amount: CGFloat) -> CGFloat {
        width * amount
    }

    private func knob(width: CGFloat, amount: CGFloat) -> some View {
        ZStack {
            knobFill(width: width, amount: amount)

            Capsule()
                .strokeBorder(tint.opacity(0.22), lineWidth: 0.8)
        }
        .shadow(color: tint.opacity(0.10), radius: 3)
        .shadow(
            color: Color.black.opacity(
                colorScheme == .light ? 0.05 : 0.12
            ),
            radius: 2,
            y: 1
        )
    }

    @ViewBuilder
    private func knobFill(width: CGFloat, amount: CGFloat) -> some View {
        if reduceTransparency {
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    Capsule()
                        .fill(
                            tint.opacity(
                                colorScheme == .light ? 0.10 : 0.16
                            )
                        )
                )
        } else {
            ZStack(alignment: .leading) {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(trackOpacity))
                        .frame(width: width, height: trackHeight)

                    Capsule()
                        .fill(tint)
                        .frame(
                            width: fillWidth(width: width, amount: amount),
                            height: trackHeight
                        )
                }
                .padding(.horizontal, knobWidth)
                .offset(
                    x: -(knobWidth / 2 + width * amount)
                )
                .blur(radius: 2)

                Capsule()
                    .fill(.ultraThinMaterial)
                    .opacity(0.5)
                    .frame(width: knobWidth, height: knobHeight)
            }
            .frame(
                width: knobWidth,
                height: knobHeight,
                alignment: .leading
            )
            .clipShape(Capsule())
        }
    }

    private func updateValue(at x: CGFloat, width: CGFloat) {
        let normalized = min(max(x / max(width, 1), 0), 1)
        value = Double(normalized)
    }
}
