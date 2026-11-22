import SwiftUI

struct MusicLyricsView: View {
    let snapshot: MusicSnapshot
    let state: LyricsController.State
    let width: CGFloat
    let height: CGFloat
    let onBack: () -> Void
    let onRetry: () -> Void

    private var slotHeight: CGFloat {
        min(32, max(22, (height - 20) / 3))
    }

    var body: some View {
        Group {
            switch state {
            case .synced(let trackID, let lyrics)
                where trackID == snapshot.trackID:
                syncedView(lyrics)
            case .plain(let trackID, let text)
                where trackID == snapshot.trackID:
                plainView(text)
            case .instrumental(let trackID)
                where trackID == snapshot.trackID:
                message("纯音乐，请欣赏")
            case .unavailable(let trackID)
                where trackID == snapshot.trackID:
                message("暂时找不到这首歌的歌词")
            case .failed(let trackID)
                where trackID == snapshot.trackID:
                failureView
            default:
                loadingView
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .overlay(alignment: .topLeading) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .frame(width: 23, height: 23)
                    .background(
                        Circle().fill(Color.black.opacity(0.26))
                    )
                    .overlay {
                        Circle().stroke(
                            Color.white.opacity(0.06),
                            lineWidth: 0.5
                        )
                    }
            }
            .buttonStyle(.plain)
            .help("返回播放界面")
            .accessibilityLabel("返回播放界面")
        }
        .environment(\.colorScheme, .dark)
    }

    private func syncedView(_ lyrics: SyncedLyrics) -> some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 60.0,
                paused: !snapshot.isPlaying
            )
        ) { context in
            let position = snapshot.elapsed(at: context.date)
            let active = lyrics.activeIndex(at: position)
            let scroll = scrollPosition(
                lyrics,
                at: position,
                active: active
            )
            let anchor = Int(scroll.rounded())
            let lower = max(0, anchor - 3)
            let upper = min(lyrics.lines.count - 1, anchor + 2)

            ZStack {
                ForEach(lower...upper, id: \.self) { index in
                    let line = lyrics.lines[index]

                    LyricLineView(
                        text: line.text,
                        isActive: index == active,
                        progress: index == active
                            ? lyrics.progress(for: index, at: position)
                            : 0,
                        scrollDistance: CGFloat(index) - CGFloat(scroll)
                    )
                    .offset(
                        y: (CGFloat(index) - scroll) * slotHeight
                            + slotHeight / 2
                            - 7
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.04),
                        .init(color: .black, location: 0.97),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .padding(.horizontal, 10)
        }
    }

    private func scrollPosition(
        _ lyrics: SyncedLyrics,
        at position: TimeInterval,
        active: Int?
    ) -> Double {
        guard let active, active + 1 < lyrics.lines.count else {
            return Double(active ?? 0)
        }

        let currentStart = lyrics.lines[active].start
        let nextStart = lyrics.lines[active + 1].start
        let lead = min(0.42, max(0.12, (nextStart - currentStart) * 0.45))
        let scrollStart = nextStart - lead
        guard position > scrollStart else { return Double(active) }

        let progress = min(max((position - scrollStart) / lead, 0), 1)
        let eased = progress * progress * (3 - 2 * progress)
        return Double(active) + eased
    }

    private func plainView(_ text: String) -> some View {
        ScrollView(.vertical) {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.56))
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.12),
                    .init(color: .black, location: 0.88),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(.white.opacity(0.55))

            Text("正在获取歌词")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func message(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "quote.bubble")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))

            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failureView: some View {
        VStack(spacing: 10) {
            Text("歌词获取失败")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))

            Button(action: onRetry) {
                Text("重试")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Color.white.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LyricLineView: View {
    let text: String
    let isActive: Bool
    let progress: Double
    let scrollDistance: CGFloat

    private var depth: CGFloat {
        min(abs(scrollDistance), 3)
    }

    private var emphasis: CGFloat {
        max(0, 1 - min(abs(scrollDistance), 1))
    }

    private var baseOpacity: Double {
        0.42 + Double(1 - emphasis) * 0.5
    }

    private var opacity: Double {
        let value = Double(depth)
        if value <= 1 {
            return 1 - 0.48 * value
        }
        if value <= 2 {
            return 0.52 - 0.26 * (value - 1)
        }
        return max(0.12, 0.26 - 0.14 * (value - 2))
    }

    private var scale: CGFloat {
        1 - min(depth, 2) * 0.05
    }

    private var blur: CGFloat {
        if depth <= 1 {
            return depth * 0.9
        }
        if depth <= 2 {
            return 0.9 + (depth - 1) * 0.6
        }
        return min(2, 1.5 + (depth - 2) * 0.5)
    }

    var body: some View {
        ZStack {
            Text(text)
                .foregroundStyle(Color.white.opacity(baseOpacity))

            if isActive {
                Text(text)
                    .foregroundStyle(Color.white.opacity(0.96))
                    .accessibilityHidden(true)
                    .mask(alignment: .leading) {
                        GeometryReader { proxy in
                            Rectangle()
                                .frame(
                                    width: proxy.size.width
                                        * CGFloat(min(max(progress, 0), 1))
                                )
                        }
                    }
            }
        }
        .font(
            .system(
                size: 14.5,
                weight: .medium,
                design: .rounded
            )
        )
        .lineLimit(1)
        .minimumScaleFactor(0.68)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .scaleEffect(scale)
        .opacity(opacity)
        .blur(radius: blur)
    }
}
