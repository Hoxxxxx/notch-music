import AppKit
import SwiftUI

private enum LyricsMetrics {
    static let fontSize: CGFloat = 14.5
    static let compactActiveFontSize: CGFloat = 16
    static let compactInactiveFontSize: CGFloat = 12.5
    static let notchActiveFontSize: CGFloat = 16.5
    static let notchInactiveFontSize: CGFloat = 13.5
    static let lineSpacing: CGFloat = 2

    static var font: Font {
        font(ofSize: fontSize)
    }

    static func font(ofSize size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }

    static var nsFont: NSFont {
        nsFont(ofSize: fontSize)
    }

    static func nsFont(ofSize size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: .medium)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded),
              let font = NSFont(descriptor: descriptor, size: size)
        else {
            return base
        }
        return font
    }

    static var lineHeight: CGFloat {
        lineHeight(forSize: fontSize)
    }

    static func lineHeight(forSize size: CGFloat) -> CGFloat {
        let font = nsFont(ofSize: size)
        return ceil(font.ascender - font.descender + font.leading)
    }
}

private struct LyricsScrollLayout {
    let centers: [CGFloat]
    let rowWeights: [[Double]]
    let slotHeight: CGFloat

    init(
        lines: [LyricLine],
        textWidth: CGFloat,
        slotHeight: CGFloat,
        fontSize: CGFloat
    ) {
        self.slotHeight = slotHeight

        let measurements = lines.map {
            Self.measure(
                $0.text,
                width: textWidth,
                fontSize: fontSize
            )
        }
        let heights = measurements.map(\.height)
        self.rowWeights = measurements.map(\.rowWeights)
        let gap = max(
            2,
            slotHeight - LyricsMetrics.lineHeight(forSize: fontSize)
        )
        var centers: [CGFloat] = []
        centers.reserveCapacity(heights.count)
        var cursor: CGFloat = 0

        for (index, height) in heights.enumerated() {
            centers.append(cursor + height / 2)
            cursor += height
            if index < heights.count - 1 {
                cursor += gap
            }
        }

        self.centers = centers
    }

    func center(at scroll: Double) -> CGFloat {
        guard !centers.isEmpty else { return 0 }

        let clamped = min(max(scroll, 0), Double(centers.count - 1))
        let lower = Int(clamped.rounded(.down))
        let upper = min(lower + 1, centers.count - 1)
        let progress = CGFloat(clamped - Double(lower))
        return centers[lower]
            + (centers[upper] - centers[lower]) * progress
    }

    func offset(for index: Int, at centerY: CGFloat) -> CGFloat {
        centers[index] - centerY
    }

    func scrollDistance(for index: Int, at centerY: CGFloat) -> CGFloat {
        guard slotHeight > 0 else { return 0 }
        return (centers[index] - centerY) / slotHeight
    }

    private static func measure(
        _ text: String,
        width: CGFloat,
        fontSize: CGFloat
    ) -> (height: CGFloat, rowWeights: [Double]) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = LyricsMetrics.lineSpacing
        let attributes: [NSAttributedString.Key: Any] = [
            .font: LyricsMetrics.nsFont(ofSize: fontSize),
            .paragraphStyle: paragraph
        ]
        let rect = (text as NSString).boundingRect(
            with: CGSize(
                width: max(width, 1),
                height: .greatestFiniteMagnitude
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        let height = max(
            ceil(rect.height),
            LyricsMetrics.lineHeight(forSize: fontSize)
        )

        let textStorage = NSTextStorage(
            string: text,
            attributes: attributes
        )
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            containerSize: CGSize(
                width: max(width, 1),
                height: .greatestFiniteMagnitude
            )
        )
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        let nsText = text as NSString
        var rowWeights: [Double] = []
        var glyphIndex = 0

        while glyphIndex < layoutManager.numberOfGlyphs {
            var glyphRange = NSRange()
            _ = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: &glyphRange
            )
            let characterRange = layoutManager.characterRange(
                forGlyphRange: glyphRange,
                actualGlyphRange: nil
            )
            let row = nsText.substring(with: characterRange)
            let count = row
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .count
            rowWeights.append(Double(max(count, 1)))
            glyphIndex = NSMaxRange(glyphRange)
        }

        return (height, rowWeights.isEmpty ? [1] : rowWeights)
    }
}

struct MusicLyricsView: View {
    let snapshot: MusicSnapshot
    let state: LyricsController.State
    let width: CGFloat
    let height: CGFloat
    var showsBackButton = true
    var compact = false
    var alignsLeading = false
    let onBack: () -> Void
    let onRetry: () -> Void

    private var slotHeight: CGFloat {
        if compact {
            return min(27, max(21, (height + 6) / 3))
        }
        return min(32, max(22, (height - 20) / 3))
    }

    private var horizontalPadding: CGFloat {
        compact ? 4 : 10
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
            if showsBackButton {
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
        }
        .environment(\.colorScheme, .dark)
    }

    private func syncedView(_ lyrics: SyncedLyrics) -> some View {
        let layout = LyricsScrollLayout(
            lines: lyrics.lines,
            textWidth: max(
                width - horizontalPadding * 2,
                1
            ),
            slotHeight: slotHeight,
            fontSize: compact
                ? LyricsMetrics.compactActiveFontSize
                : LyricsMetrics.notchActiveFontSize
        )
        let verticalBias: CGFloat = compact ? 0 : slotHeight / 2 - 7

        return Group {
            if lyrics.lines.isEmpty {
                EmptyView()
            } else {
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
                    let upper = min(lyrics.lines.count - 1, anchor + 3)
                    let centerY = layout.center(at: scroll)

                    ZStack {
                        ForEach(lower...upper, id: \.self) { index in
                            let line = lyrics.lines[index]

                            LyricLineView(
                                text: line.text,
                                isActive: index == active,
                                rowWeights: layout.rowWeights[index],
                                progress: index == active
                                    ? lyrics.progress(
                                        for: index,
                                        at: position
                                    )
                                    : 0,
                                scrollDistance: layout.scrollDistance(
                                    for: index,
                                    at: centerY
                                ),
                                compact: compact,
                                alignsLeading: alignsLeading
                            )
                            .offset(
                                y: layout.offset(
                                    for: index,
                                    at: centerY
                                ) + verticalBias
                            )
                        }
                    }
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(
                                    color: .black,
                                    location: 0.04
                                ),
                                .init(
                                    color: .black,
                                    location: compact ? 0.96 : 0.97
                                ),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .padding(.horizontal, horizontalPadding)
                }
            }
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
                .multilineTextAlignment(
                    alignsLeading ? .leading : .center
                )
                .lineSpacing(6)
                .frame(
                    maxWidth: .infinity,
                    alignment: alignsLeading ? .leading : .center
                )
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
    let rowWeights: [Double]
    let progress: Double
    let scrollDistance: CGFloat
    let compact: Bool
    let alignsLeading: Bool

    private var depth: CGFloat {
        min(abs(scrollDistance), 3)
    }

    private var fontSize: CGFloat {
        let emphasis = 1 - min(abs(scrollDistance), 1)
        let inactiveSize = compact
            ? LyricsMetrics.compactInactiveFontSize
            : LyricsMetrics.notchInactiveFontSize
        let activeSize = compact
            ? LyricsMetrics.compactActiveFontSize
            : LyricsMetrics.notchActiveFontSize
        return inactiveSize + (activeSize - inactiveSize) * emphasis
    }

    private var baseOpacity: Double {
        if isActive {
            return 0.34
        }
        return 0.5
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

    private var blur: CGFloat {
        if depth <= 1 {
            return depth * 0.9
        }
        if depth <= 2 {
            return 0.9 + (depth - 1) * 0.6
        }
        return min(2, 1.5 + (depth - 2) * 0.5)
    }

    private var styledText: some View {
        Text(text)
            .font(LyricsMetrics.font(ofSize: fontSize))
            .multilineTextAlignment(alignsLeading ? .leading : .center)
            .lineSpacing(LyricsMetrics.lineSpacing)
            .fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        ZStack {
            styledText
                .foregroundStyle(Color.white.opacity(baseOpacity))

            if isActive {
                styledText
                    .foregroundStyle(Color.white)
                    .accessibilityHidden(true)
                    .mask(alignment: .topLeading) {
                        GeometryReader { proxy in
                            let weights = rowWeights.isEmpty
                                ? [1]
                                : rowWeights
                            let total = max(
                                weights.reduce(0, +),
                                1
                            )
                            let spacing = LyricsMetrics.lineSpacing
                            let rowHeight = max(
                                1,
                                (
                                    proxy.size.height
                                        - CGFloat(weights.count - 1)
                                            * spacing
                                ) / CGFloat(weights.count)
                            )
                            let fill = min(max(progress, 0), 1)
                                * total

                            VStack(
                                alignment: .leading,
                                spacing: spacing
                            ) {
                                ForEach(
                                    weights.indices,
                                    id: \.self
                                ) { row in
                                    let start = weights
                                        .prefix(row)
                                        .reduce(0, +)
                                    let rowFill = min(
                                        max(
                                            (fill - start)
                                                / weights[row],
                                            0
                                        ),
                                        1
                                    )
                                    Rectangle()
                                        .frame(
                                            width: proxy.size.width
                                                * CGFloat(rowFill),
                                            height: rowHeight
                                        )
                                }
                            }
                        }
                    }
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: alignsLeading ? .leading : .center
        )
        .opacity(opacity)
        .blur(radius: blur)
    }
}
