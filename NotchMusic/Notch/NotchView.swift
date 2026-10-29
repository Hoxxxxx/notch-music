import AppKit
import SwiftUI

struct NotchView: View {
    @ObservedObject var musicMonitor: MusicMonitor
    @ObservedObject var panelState: NotchPanelState

    @State private var scrubPosition: TimeInterval?
    @State private var showsVolumeSlider = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Color {
        Color(nsColor: musicMonitor.snapshot?.accentColor ?? ArtworkPalette.fallback)
    }

    var body: some View {
        let isPlaying = musicMonitor.snapshot?.isPlaying == true
        let size = CGSize(
            width: panelState.isExpanded
                ? NotchLayout.expandedWidth(notchWidth: panelState.notchWidth)
                : NotchLayout.compactWidth(
                    notchWidth: panelState.notchWidth,
                    isPlaying: isPlaying
                ),
            height: panelState.isExpanded ? NotchLayout.expandedHeight : panelState.topInset
        )
        let cornerRadius: CGFloat = panelState.isExpanded ? 22 : 14

        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                NotchBackdrop(
                    cornerRadius: cornerRadius,
                    artwork: musicMonitor.snapshot?.artwork,
                    accent: accent,
                    isExpanded: panelState.isExpanded,
                    topInset: panelState.topInset
                )

                if panelState.isExpanded {
                    expandedContent
                        .transition(.opacity)
                } else if isPlaying {
                    compactContent
                        .transition(.opacity)
                }

                if let snapshot = musicMonitor.snapshot,
                   panelState.isExpanded || isPlaying {
                    let artworkSize: CGFloat = panelState.isExpanded ? 88 : 22

                    artworkView(snapshot.artwork, size: artworkSize)
                        .offset(
                            x: panelState.isExpanded ? 16 : 6,
                            y: panelState.isExpanded
                                ? 42
                                : (panelState.topInset - artworkSize) / 2
                        )
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(NotchShape(cornerRadius: cornerRadius))
            .shadow(
                color: panelState.isExpanded ? .black.opacity(0.65) : .clear,
                radius: 6,
                y: 2
            )
            .overlay {
                NotchShape(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            }
            .contentShape(NotchShape(cornerRadius: cornerRadius))
            .onHover { hovering in
                panelState.setHovering(hovering)
            }
            .onTapGesture {
                panelState.expand()
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(
            expansionAnimation,
            value: panelState.isExpanded
        )
        .animation(
            .spring(response: 0.34, dampingFraction: 0.9),
            value: isPlaying
        )
    }

    private var expansionAnimation: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.18)
        }

        return panelState.isExpanded
            ? .spring(response: 0.50, dampingFraction: 0.74, blendDuration: 0)
            : .spring(response: 0.52, dampingFraction: 0.74, blendDuration: 0)
    }

    private var compactContent: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: 22, height: 22)

            Spacer(minLength: 0)

            CompactPlaybackIndicator(color: accent)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var expandedContent: some View {
        Group {
            if let snapshot = musicMonitor.snapshot {
                nowPlaying(snapshot)
            } else {
                emptyState
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 42)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func nowPlaying(_ snapshot: MusicSnapshot) -> some View {
        VStack(spacing: 9) {
            HStack(alignment: .top, spacing: 14) {
                Color.clear
                    .frame(width: 88, height: 88)

                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(snapshot.artist.isEmpty ? "Apple Music" : snapshot.artist)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)

                    Text(snapshot.album.isEmpty ? " " : snapshot.album)
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    playbackControls(snapshot)
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
            }

            playbackProgress(snapshot)
        }
    }

    private func playbackProgress(_ snapshot: MusicSnapshot) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = snapshot.elapsed(at: context.date)
            let displayedPosition = scrubPosition ?? elapsed

            VStack(spacing: 4) {
                AccentProgressSlider(
                    value: displayedPosition,
                    range: 0...max(snapshot.duration, 1),
                    color: Color(nsColor: snapshot.accentColor),
                    isEnabled: snapshot.duration > 0 && !musicMonitor.isSendingCommand,
                    onChange: { scrubPosition = $0 },
                    onEditingStarted: {
                        if scrubPosition == nil {
                            scrubPosition = elapsed
                        }
                    },
                    onCommit: { position in
                        musicMonitor.seek(to: position)
                        scrubPosition = nil
                    }
                )

                HStack {
                    Text(timeString(displayedPosition))
                    Spacer()
                    Text(timeString(snapshot.duration))
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.42))
            }
        }
    }

    private func playbackControls(_ snapshot: MusicSnapshot) -> some View {
        HStack(spacing: 6) {
            PlaybackButton(
                systemName: "backward.fill",
                label: "上一首",
                accent: accent,
                action: musicMonitor.previousTrack
            )

            PlaybackButton(
                systemName: snapshot.isPlaying ? "pause.fill" : "play.fill",
                label: snapshot.isPlaying ? "暂停" : "播放",
                accent: accent,
                emphasized: true,
                action: musicMonitor.togglePlayPause
            )

            PlaybackButton(
                systemName: "forward.fill",
                label: "下一首",
                accent: accent,
                action: musicMonitor.nextTrack
            )

            Spacer(minLength: 4)

            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    showsVolumeSlider.toggle()
                }
            } label: {
                Image(systemName: volumeIcon(snapshot.volume))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.76))
                    .frame(width: 25, height: 25)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("音量")
            .accessibilityLabel("音量")

            if showsVolumeSlider {
                Slider(
                    value: Binding(
                        get: { snapshot.volume },
                        set: { musicMonitor.setVolume($0) }
                    ),
                    in: 0...1
                )
                .controlSize(.mini)
                .tint(accent)
                .frame(width: 54)
                .accessibilityLabel("Apple Music 音量")
                .transition(
                    .opacity.combined(
                        with: .scale(scale: 0.85, anchor: .trailing)
                    )
                )
            }
        }
        .disabled(musicMonitor.isSendingCommand)
        .opacity(musicMonitor.isSendingCommand ? 0.55 : 1)
    }

    private func volumeIcon(_ volume: Double) -> String {
        if volume == 0 {
            return "speaker.slash.fill"
        }
        if volume < 0.33 {
            return "speaker.1.fill"
        }
        if volume < 0.66 {
            return "speaker.2.fill"
        }
        return "speaker.3.fill"
    }

    private func artworkView(_ artwork: NSImage?, size: CGFloat) -> some View {
        Group {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.15),
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Image(systemName: "music.note")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white.opacity(0.56))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(
            RoundedRectangle(
                cornerRadius: panelState.isExpanded ? 12 : 6,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: panelState.isExpanded ? 12 : 6,
                style: .continuous
            )
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        }
    }

    private var emptyState: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.08))

                Image(systemName: stateIcon)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(.white.opacity(0.66))
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 5) {
                Text(stateTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text(stateDescription)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.54))
                    .lineLimit(2)

                if let primaryAction {
                    Button(primaryAction.title, action: primaryAction.action)
                        .buttonStyle(NotchActionButtonStyle())
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var stateTitle: String {
        if !musicMonitor.isConnected {
            return "连接 Apple Music"
        }
        if musicMonitor.needsPermission {
            return "需要自动化权限"
        }
        if !musicMonitor.isMusicRunning {
            return "Apple Music 未运行"
        }
        if musicMonitor.errorMessage != nil {
            return "读取失败"
        }
        return "没有正在播放的音乐"
    }

    private var stateDescription: String {
        if !musicMonitor.isConnected {
            return "授权后，刘海会显示当前播放的歌曲。"
        }
        if musicMonitor.needsPermission {
            return "在系统设置中允许 NotchMusic 控制 Apple Music。"
        }
        if !musicMonitor.isMusicRunning {
            return "播放音乐后会自动显示在这里。"
        }
        if let errorMessage = musicMonitor.errorMessage {
            return errorMessage
        }
        return "在 Apple Music 中选择一首歌曲。"
    }

    private var stateIcon: String {
        if !musicMonitor.isConnected {
            return "link"
        }
        if musicMonitor.needsPermission {
            return "lock.open"
        }
        if !musicMonitor.isMusicRunning {
            return "music.note"
        }
        if musicMonitor.errorMessage != nil {
            return "exclamationmark.triangle"
        }
        return "waveform"
    }

    private var primaryAction: (title: String, action: () -> Void)? {
        if !musicMonitor.isConnected {
            return ("连接", { musicMonitor.connect() })
        }
        if musicMonitor.needsPermission {
            return ("打开系统设置", { musicMonitor.openAutomationSettings() })
        }
        if !musicMonitor.isMusicRunning {
            return ("打开 Apple Music", { musicMonitor.openAppleMusic() })
        }
        if musicMonitor.errorMessage != nil {
            return ("重试", { musicMonitor.refreshNow() })
        }
        return ("刷新", { musicMonitor.refreshNow() })
    }

    private func timeString(_ value: TimeInterval) -> String {
        guard value.isFinite, value >= 0 else { return "0:00" }
        let total = Int(value.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct AccentProgressSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let color: Color
    let isEnabled: Bool
    let onChange: (Double) -> Void
    let onEditingStarted: () -> Void
    let onCommit: (Double) -> Void

    @State private var isEditing = false

    private let thumbSize: CGFloat = 14

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let usableWidth = max(width - thumbSize, 0)
            let fraction = valueFraction
            let thumbOffset = usableWidth * fraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.16))
                    .frame(height: 3)

                Capsule()
                    .fill(color)
                    .frame(width: thumbOffset + thumbSize / 2, height: 3)

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .offset(x: thumbOffset)
            }
            .frame(width: width, height: thumbSize)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard isEnabled else { return }
                        if !isEditing {
                            isEditing = true
                            onEditingStarted()
                        }
                        onChange(value(at: gesture.location.x, width: width))
                    }
                    .onEnded { gesture in
                        guard isEnabled else { return }
                        let finalValue = value(at: gesture.location.x, width: width)
                        onChange(finalValue)
                        isEditing = false
                        onCommit(finalValue)
                    }
            )
        }
        .frame(height: thumbSize)
        .opacity(isEnabled ? 1 : 0.5)
        .allowsHitTesting(isEnabled)
        .accessibilityElement()
        .accessibilityLabel("播放进度")
        .accessibilityValue("\(Int(valueFraction * 100))%")
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            let span = range.upperBound - range.lowerBound
            let step = max(span / 100, 1)
            let adjusted = direction == .increment ? value + step : value - step
            let clamped = min(max(adjusted, range.lowerBound), range.upperBound)
            onChange(clamped)
            onCommit(clamped)
        }
    }

    private var valueFraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    private func value(at x: CGFloat, width: CGFloat) -> Double {
        let usableWidth = max(width - thumbSize, 1)
        let fraction = min(max((x - thumbSize / 2) / usableWidth, 0), 1)
        let span = range.upperBound - range.lowerBound
        return range.lowerBound + span * fraction
    }
}

private struct NotchBackdrop: View {
    let cornerRadius: CGFloat
    let artwork: NSImage?
    let accent: Color
    let isExpanded: Bool
    let topInset: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                        .clipped()
                        .scaleEffect(1.3)
                        .saturation(1.55)
                        .contrast(1.08)
                        .brightness(0.08)
                        .blur(radius: 32)
                        .opacity(isExpanded ? 0.9 : 0)
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .white, location: 0),
                                    .init(color: .white.opacity(0.94), location: 0.24),
                                    .init(color: .white.opacity(0.22), location: 0.48),
                                    .init(color: .clear, location: 0.62)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    RadialGradient(
                        colors: [
                            accent.opacity(0.2),
                            .clear
                        ],
                        center: UnitPoint(x: 0.08, y: 0.32),
                        startRadius: 0,
                        endRadius: geometry.size.width * 0.58
                    )
                    .blendMode(.screen)
                } else if isExpanded {
                    RadialGradient(
                        colors: [
                            accent.opacity(0.34),
                            .black.opacity(0.92)
                        ],
                        center: .bottomLeading,
                        startRadius: 0,
                        endRadius: geometry.size.width
                    )
                }

                LinearGradient(
                    stops: [
                        .init(
                            color: .black.opacity(isExpanded ? 0.18 : 0),
                            location: 0
                        ),
                        .init(
                            color: .black.opacity(isExpanded ? 0.62 : 0),
                            location: 0.52
                        ),
                        .init(
                            color: .black.opacity(isExpanded ? 0.86 : 0),
                            location: 1
                        )
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if artwork != nil, isExpanded {
                    RadialGradient(
                        colors: [
                            .black.opacity(0.42),
                            .clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: max(
                            geometry.size.width,
                            geometry.size.height
                        ) * 0.68
                    )
                }

                VStack(spacing: 0) {
                    Color.black
                        .frame(height: topInset + 1)

                    LinearGradient(
                        colors: [
                            .black,
                            .black.opacity(0.72),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 24)

                    Spacer(minLength: 0)
                }
            }
        }
        .clipShape(NotchShape(cornerRadius: cornerRadius))
        .accessibilityHidden(true)
        .animation(
            .easeInOut(duration: 0.36),
            value: isExpanded
        )
    }
}

private struct NotchShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, rect.height / 2)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

private struct CompactPlaybackIndicator: View {
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate

            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(width: 2.5, height: barHeight(at: time, index: index))
                }
            }
            .frame(width: 13, height: 12)
        }
        .accessibilityLabel("正在播放")
    }

    private func barHeight(at time: TimeInterval, index: Int) -> CGFloat {
        let phase = time * 3.2 + Double(index) * 1.7
        return CGFloat(4 + (sin(phase) + 1) * 3.5)
    }
}

private struct PlaybackButton: View {
    let systemName: String
    let label: String
    let accent: Color
    var emphasized = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: emphasized ? 11 : 10, weight: .bold))
                .foregroundStyle(.white.opacity(emphasized ? 1 : 0.76))
                .frame(width: 25, height: 25)
                .background(
                    emphasized ? accent : Color.white.opacity(0.12),
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct NotchActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Color.white.opacity(configuration.isPressed ? 0.22 : 0.13),
                in: Capsule()
            )
    }
}
