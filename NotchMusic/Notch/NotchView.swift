import AppKit
import SwiftUI

struct NotchView: View {
    @ObservedObject var musicMonitor: MusicMonitor
    @ObservedObject var panelState: NotchPanelState

    private let accent = Color(red: 1.0, green: 0.38, blue: 0.30)

    var body: some View {
        let cornerRadius: CGFloat = panelState.isExpanded ? 22 : 14

        ZStack {
            NotchBackdrop(cornerRadius: cornerRadius)

            if panelState.isExpanded {
                expandedContent
                    .transition(
                        .opacity.combined(
                            with: .scale(scale: 0.98, anchor: .top)
                        )
                    )
            } else {
                compactContent
                    .transition(.opacity)
            }
        }
        .clipShape(NotchShape(cornerRadius: cornerRadius))
        .overlay {
            NotchShape(cornerRadius: cornerRadius)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        }
        .contentShape(NotchShape(cornerRadius: cornerRadius))
        .onHover { hovering in
            panelState.setHovering(hovering)
        }
        .animation(
            .spring(response: 0.32, dampingFraction: 0.88),
            value: panelState.isExpanded
        )
    }

    private var compactContent: some View {
        HStack(spacing: 0) {
            compactArtwork
                .frame(width: 22, height: 22)

            Spacer(minLength: 0)

            Image(systemName: musicMonitor.snapshot?.isPlaying == true ? "waveform" : "music.note")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var compactArtwork: some View {
        Group {
            if let artwork = musicMonitor.snapshot?.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.62))
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
        HStack(alignment: .top, spacing: 14) {
            artworkView(snapshot.artwork, size: 78)

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

                Spacer(minLength: 6)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed = snapshot.elapsed(at: context.date)
                    VStack(spacing: 5) {
                        ProgressBar(
                            progress: snapshot.duration > 0
                                ? snapshot.progress(at: context.date)
                                : 0,
                            accent: accent
                        )

                        HStack {
                            Text(timeString(elapsed))
                            Spacer()
                            Text(timeString(snapshot.duration))
                        }
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.42))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
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

private struct NotchBackdrop: View {
    let cornerRadius: CGFloat

    var body: some View {
        NotchShape(cornerRadius: cornerRadius)
            .fill(
                LinearGradient(
                    colors: [
                        .black,
                        Color(red: 0.025, green: 0.025, blue: 0.03)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
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

private struct ProgressBar: View {
    let progress: Double
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.14))

                Capsule()
                    .fill(accent)
                    .frame(width: max(0, proxy.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: 3)
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
