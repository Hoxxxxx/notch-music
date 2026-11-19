import AppKit
import SwiftUI

struct NotchBackdrop: View {
    let topCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat
    let artwork: NSImage?
    let accent: Color
    let bottomBackground: Color
    let isPlaying: Bool
    let backgroundEnabled: Bool
    let alwaysVisible: Bool
    let backgroundEffect: NotchBackgroundEffect
    let spectrumLevels: [CGFloat]
    let isExpanded: Bool
    let topInset: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                if artwork == nil, isExpanded {
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
                            color: .black.opacity(isExpanded ? 0.24 : 0),
                            location: 0
                        ),
                        .init(
                            color: .black.opacity(isExpanded ? 0.70 : 0),
                            location: 0.42
                        ),
                        .init(
                            color: .black.opacity(isExpanded ? 0.92 : 0),
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

                if backgroundEnabled && (isPlaying || alwaysVisible) {
                    NotchBackgroundView(
                        effect: backgroundEffect,
                        accent: bottomBackground,
                        artwork: artwork,
                        isPlaying: isPlaying,
                        spectrumLevels: spectrumLevels
                    )
                        .transition(.opacity)
                }

                VStack(spacing: 0) {
                    Color.black
                        .frame(height: topInset + 1)

                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black.opacity(0.82), location: 0.32),
                            .init(color: .black.opacity(0.40), location: 0.66),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 18)

                    Spacer(minLength: 0)
                }

            }
        }
        .clipShape(
            NotchShape(
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius
            )
        )
        .accessibilityHidden(true)
        .animation(
            .easeInOut(duration: 0.4),
            value: isPlaying
        )
        .animation(
            .easeInOut(duration: 0.25),
            value: alwaysVisible
        )
    }
}

private struct NotchBackgroundView: View {
    let effect: NotchBackgroundEffect
    let accent: Color
    let artwork: NSImage?
    let isPlaying: Bool
    let spectrumLevels: [CGFloat]

    @ViewBuilder
    var body: some View {
        switch effect {
        case .aurora:
            AuroraGlow(accent: accent)
        case .gradientWaves:
            GradientWavesBackground(accent: accent)
        case .aeroShards:
            AeroShardsBackground(accent: accent)
        case .pixelMatrix:
            PixelMatrixBackground(accent: accent)
        case .spectrum:
            SpectrumBackground(
                levels: spectrumLevels,
                accent: accent
            )
        case .albumFlow:
            AlbumFlowBackground(
                accent: accent,
                artwork: artwork,
                isPlaying: isPlaying
            )
        default:
            ProceduralNotchBackground(
                effect: effect,
                accent: accent
            )
        }
    }
}

private struct AlbumFlowBackground: View {
    let accent: Color
    let artwork: NSImage?
    let isPlaying: Bool

    @ObservedObject private var library = AlbumArtworkLibrary.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var covers: [NSImage] {
        if !library.covers.isEmpty { return library.covers }
        if let artwork { return [artwork] }
        return []
    }

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: reduceMotion || !isPlaying
            )
        ) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                draw(in: &context, size: size, time: time)
            }
        }
        .overlay(alignment: .bottom) {
            RadialGradient(
                colors: [
                    accent.opacity(0.34),
                    accent.opacity(0.10),
                    .clear
                ],
                center: .bottom,
                startRadius: 4,
                endRadius: 210
            )
            .blendMode(.plusLighter)
        }
        .overlay {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.10), location: 0),
                    .init(color: .black.opacity(0.40), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.01),
                    .init(color: .white.opacity(0.28), location: 0.13),
                    .init(color: .white.opacity(0.82), location: 0.27),
                    .init(color: .white, location: 0.42)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .task {
            AlbumArtworkLibrary.shared.ensureLoaded()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        guard size.width > 1, size.height > 1 else { return }
        let images = covers
        guard !images.isEmpty else { return }

        var layer = context
        layer.addFilter(.saturation(0.95))

        let side = max(48, size.height * 0.35)
        let step = side - 0.5
        let columns = max(3, Int(ceil(size.width / step)) + 1)
        let rows = max(2, Int(ceil(size.height / step)) + 1)
        let driftX = CGFloat(sin(time * 0.06)) * 5
        let driftY = CGFloat(cos(time * 0.05)) * 4
        let originX = (size.width - CGFloat(columns) * step) / 2 + driftX
        let originY = (size.height - CGFloat(rows) * step) / 2 - 30 + driftY

        for row in 0..<rows {
            for column in 0..<columns {
                let index = row * columns + column
                let period = 13.0 + EffectMath.hash(index + 11) * 7
                let cyclePosition =
                    time / period + EffectMath.hash(index + 3) * 4
                let cycle = floor(cyclePosition)
                let fade = smoothStep(
                    min(1, (cyclePosition - cycle) / 0.18)
                )
                let first = images[
                    positiveModulo(Int(cycle) + index, images.count)
                ]
                let second = images[
                    positiveModulo(Int(cycle) + index + 1, images.count)
                ]

                let rect = CGRect(
                    x: -side / 2,
                    y: -side / 2,
                    width: side,
                    height: side
                )

                var cell = layer
                cell.translateBy(
                    x: originX + (CGFloat(column) + 0.5) * step,
                    y: originY + (CGFloat(row) + 0.5) * step
                )
                cell.clip(to: Path(rect))

                if fade < 0.999 {
                    var outgoing = cell
                    if EffectMath.hash(index + Int(cycle) + 101) > 0.5 {
                        outgoing.scaleBy(x: -1, y: 1)
                    }
                    if EffectMath.hash(index + Int(cycle) + 211) > 0.72 {
                        outgoing.scaleBy(x: 1, y: -1)
                    }
                    outgoing.opacity = 0.58 * (1 - fade)
                    outgoing.draw(Image(nsImage: first), in: rect)
                }

                if fade > 0.001 {
                    var incoming = cell
                    if EffectMath.hash(index + Int(cycle) + 102) > 0.5 {
                        incoming.scaleBy(x: -1, y: 1)
                    }
                    if EffectMath.hash(index + Int(cycle) + 212) > 0.72 {
                        incoming.scaleBy(x: 1, y: -1)
                    }
                    incoming.opacity = 0.58 * fade
                    incoming.draw(Image(nsImage: second), in: rect)
                }
            }
        }
    }

    private func smoothStep(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    private func positiveModulo(_ value: Int, _ divisor: Int) -> Int {
        guard divisor > 0 else { return 0 }
        let remainder = value % divisor
        return remainder >= 0 ? remainder : remainder + divisor
    }
}

private struct SpectrumBackground: View {
    let levels: [CGFloat]
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: reduceMotion
            )
        ) { timeline in
            GeometryReader { geometry in
                ZStack {
                    RadialGradient(
                        colors: [
                            accent.opacity(0.24),
                            accent.opacity(0.08),
                            .clear
                        ],
                        center: .bottom,
                        startRadius: 4,
                        endRadius: max(geometry.size.width * 0.72, 180)
                    )

                    Canvas { context, size in
                        guard size.width > 0, size.height > 0 else { return }

                        let time = timeline.date.timeIntervalSinceReferenceDate
                        let usesLiveLevels = levels.contains { $0 > 0.015 }
                        let barCount = 52
                        let gap: CGFloat = 2
                        let barWidth = max(
                            1.5,
                            (size.width - CGFloat(barCount - 1) * gap)
                                / CGFloat(barCount)
                        )
                        let maximumHeight = size.height * 0.72
                        let bars = (0..<barCount).map { index in
                            let distance = abs(
                                CGFloat(index) / CGFloat(barCount - 1) - 0.5
                            ) * 2
                            let envelope = CGFloat(
                                pow(Double(max(0, 1 - distance)), 0.55)
                            )
                            let value = level(
                                at: index,
                                count: barCount,
                                time: time,
                                usesLiveLevels: usesLiveLevels
                            )
                            let height = max(
                                2,
                                maximumHeight
                                    * CGFloat(pow(Double(value), 0.72))
                                    * (0.30 + envelope * 0.70)
                            )
                            let rect = CGRect(
                                x: CGFloat(index) * (barWidth + gap),
                                y: size.height - height,
                                width: barWidth,
                                height: height
                            )
                            return (
                                path: Path(
                                    roundedRect: rect,
                                    cornerRadius: barWidth / 2
                                ),
                                rect: rect,
                                opacity: 0.18 + Double(value) * 0.82
                            )
                        }

                        context.drawLayer { glow in
                            glow.addFilter(.blur(radius: 6))

                            for bar in bars {
                                glow.fill(
                                    bar.path,
                                    with: .color(
                                        accent.opacity(bar.opacity * 0.30)
                                    )
                                )
                            }
                        }

                        for bar in bars {
                            context.fill(
                                bar.path,
                                with: .linearGradient(
                                    Gradient(colors: [
                                        accent.opacity(bar.opacity * 0.42),
                                        accent.opacity(bar.opacity),
                                        .white.opacity(bar.opacity * 0.42)
                                    ]),
                                    startPoint: CGPoint(
                                        x: bar.rect.midX,
                                        y: bar.rect.maxY
                                    ),
                                    endPoint: CGPoint(
                                        x: bar.rect.midX,
                                        y: bar.rect.minY
                                    )
                                )
                            )
                        }
                    }
                }
            }
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.12),
                    .init(color: .white.opacity(0.62), location: 0.48),
                    .init(color: .white, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func level(
        at index: Int,
        count: Int,
        time: TimeInterval,
        usesLiveLevels: Bool
    ) -> CGFloat {
        let position = CGFloat(index) / CGFloat(max(count - 1, 1))

        guard usesLiveLevels, !levels.isEmpty else {
            let phase = Double(position)
            let wave = sin(phase * .pi * 5.2 + time * 2.15)
                + sin(phase * .pi * 11.3 - time * 1.37) * 0.34
            let pulse = 0.56 + sin(time * 1.25 + phase * 2.4) * 0.22
            let envelope = sin(phase * .pi)
            return min(max(CGFloat((pulse + wave * 0.16) * envelope), 0), 1)
        }

        let mapped = CGFloat(index) / CGFloat(max(count - 1, 1))
            * CGFloat(max(levels.count - 1, 0))
        let lower = Int(floor(mapped))
        let upper = min(lower + 1, levels.count - 1)
        let fraction = mapped - CGFloat(lower)
        let value = levels[lower] * (1 - fraction)
            + levels[upper] * fraction
        return min(max(value, 0), 1)
    }
}

private struct PixelMatrixBackground: View {
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let musicNoteGlyph = [
        "......####",
        "......####",
        "......####",
        "......###.",
        "......###.",
        "......###.",
        "###...###.",
        "#####.###.",
        "#####.###.",
        "#####.###.",
        ".#######..",
        "..#####..."
    ]

    private static let sparkleGlyph = [
        "...#...",
        "...#...",
        ".#####.",
        "#######",
        ".#####.",
        "...#...",
        "...#..."
    ]

    private static let smallSparkleGlyph = [
        ".#.",
        "###",
        ".#."
    ]

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: reduceMotion
            )
        ) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                drawMatrix(in: &context, size: size, time: time)
            }
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.28),
                    .init(color: .white.opacity(0.38), location: 0.50),
                    .init(color: .white, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawMatrix(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        guard size.width > 0, size.height > 0 else { return }

        let bounds = CGRect(origin: .zero, size: size)
        context.fill(
            Path(bounds),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: accent.opacity(0.82), location: 0),
                    .init(color: accent.opacity(0.68), location: 0.52),
                    .init(color: accent.opacity(0.42), location: 1)
                ]),
                startPoint: CGPoint(x: 0, y: size.height),
                endPoint: CGPoint(x: size.width, y: 0)
            )
        )
        context.fill(
            Path(bounds),
            with: .radialGradient(
                Gradient(colors: [
                    accent.opacity(0.18),
                    .clear
                ]),
                center: CGPoint(x: size.width * 0.46, y: size.height * 0.72),
                startRadius: 0,
                endRadius: size.width * 0.62
            )
        )
        context.fill(
            Path(bounds),
            with: .radialGradient(
                Gradient(colors: [
                    .clear,
                    .black.opacity(0.24)
                ]),
                center: CGPoint(x: size.width * 0.50, y: size.height * 0.62),
                startRadius: min(size.width, size.height) * 0.18,
                endRadius: max(size.width, size.height) * 0.72
            )
        )

        context.blendMode = .screen
        drawDotGrid(in: &context, size: size, time: time)
        drawGlyphCluster(in: &context, size: size, time: time)
    }

    private func drawDotGrid(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        let spacing = max(7.5, min(10.5, size.height * 0.052))
        let dotSize = max(1.1, spacing * 0.15)
        let columnCount = Int(size.width / spacing) + 1
        let rowCount = Int(size.height / spacing) + 1
        let scanX = CGFloat(EffectMath.fraction(time * 0.055)) * size.width
        let focus = CGPoint(x: size.width * 0.50, y: size.height * 0.70)

        for row in 0...rowCount {
            for column in 0...columnCount {
                let x = (CGFloat(column) + 0.5) * spacing
                let y = (CGFloat(row) + 0.5) * spacing
                let shimmer = 0.5 + 0.5 * sin(
                    time * 1.15
                        + Double(row) * 0.73
                        + Double(column) * 0.41
                )
                let scanDistance = abs(x - scanX) / max(size.width * 0.14, 1)
                let scanGlow = max(0, 1 - scanDistance) * 0.12
                let dx = Double(x - focus.x)
                let dy = Double(y - focus.y)
                let focusDistance = sqrt(dx * dx + dy * dy)
                let focusGlow = max(
                    0,
                    1 - focusDistance / Double(size.width * 0.58)
                ) * 0.07
                let opacity = 0.10 + shimmer * 0.08 + scanGlow + focusGlow
                let offsetX = CGFloat(
                    sin(time * 0.55 + Double(row) * 0.57)
                ) * 0.22
                let offsetY = CGFloat(
                    cos(time * 0.48 + Double(column) * 0.49)
                ) * 0.22
                let dot = CGRect(
                    x: x + offsetX - dotSize / 2,
                    y: y + offsetY - dotSize / 2,
                    width: dotSize,
                    height: dotSize
                )

                context.fill(
                    Path(dot),
                    with: .color(.white.opacity(opacity))
                )
            }
        }
    }

    private func drawGlyphCluster(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        let motifs: [(rows: [String], column: Int, row: Int)] = [
            (Self.musicNoteGlyph, 0, 3),
            (Self.smallSparkleGlyph, 13, 0),
            (Self.musicNoteGlyph, 18, 5),
            (Self.sparkleGlyph, 31, 1),
            (Self.musicNoteGlyph, 39, 2),
            (Self.smallSparkleGlyph, 53, 7)
        ]
        let cellSize = max(4.1, min(4.9, size.height * 0.037))
        let step = cellSize * 1.16
        let groupWidth = 58 * step
        let groupHeight = 17 * step
        let travelDistance = size.width + groupWidth
        let baseTravelProgress = EffectMath.fraction(time * 0.045)
        let driftY = CGFloat(cos(time * 0.27)) * 1.0
        var glyphPath = Path()
        var cells: [(rect: CGRect, opacity: Double)] = []

        for phase in [0.0, 0.5] {
            let travelProgress = EffectMath.fraction(
                baseTravelProgress + phase
            )
            let origin = CGPoint(
                x: -groupWidth + CGFloat(travelProgress) * travelDistance,
                y: size.height * 0.70 - groupHeight / 2 + driftY
            )

            for motif in motifs {
                let swayPhase = time * 1.25
                    + Double(motif.column) * 0.29
                let swayX = CGFloat(sin(swayPhase)) * 1.8
                let bobY = CGFloat(
                    cos(swayPhase * 0.78 + 0.9)
                ) * 3.0

                for (rowIndex, row) in motif.rows.enumerated() {
                    for (columnIndex, character) in row.enumerated()
                    where character == "#" {
                        let rect = CGRect(
                            x: origin.x + swayX
                                + CGFloat(motif.column + columnIndex) * step,
                            y: origin.y + bobY
                                + CGFloat(motif.row + rowIndex) * step,
                            width: cellSize,
                            height: cellSize
                        )
                        let shimmer = 0.5 + 0.5 * sin(
                            time * 1.45
                                + Double(columnIndex) * 0.42
                                + Double(rowIndex) * 0.55
                        )

                        glyphPath.addRect(rect)
                        cells.append((rect, 0.82 + shimmer * 0.16))
                    }
                }
            }
        }

        let groupPulse = 0.88 + 0.12 * sin(time * 1.35)

        context.drawLayer { glowLayer in
            glowLayer.blendMode = .screen
            glowLayer.addFilter(.blur(radius: 5.8))
            glowLayer.fill(
                glyphPath,
                with: .color(.white.opacity(0.34 * groupPulse))
            )
        }

        context.drawLayer { sharpLayer in
            sharpLayer.blendMode = .screen
            sharpLayer.addFilter(.blur(radius: 0.22))

            for cell in cells {
                sharpLayer.fill(
                    Path(cell.rect),
                    with: .color(.white.opacity(cell.opacity)))
            }
        }
    }

}

private struct GradientWavesBackground: View {
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: reduceMotion
            )
        ) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                drawWaves(in: &context, size: size, time: time)
            }
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.22),
                    .init(color: .white.opacity(0.38), location: 0.46),
                    .init(color: .white, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawWaves(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        guard size.width > 0, size.height > 0 else { return }

        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(colors: [
                    accent.opacity(0.20),
                    accent.opacity(0.055),
                    .clear
                ]),
                center: CGPoint(x: size.width * 0.52, y: size.height * 0.74),
                startRadius: 0,
                endRadius: size.width * 0.58
            )
        )

        for layer in (0..<5).reversed() {
            let depth = Double(layer) / 4
            let baseY = size.height * CGFloat(0.43 + depth * 0.13)
            let amplitude = size.height * CGFloat(0.10 + depth * 0.045)
            let frequency = 0.92 + depth * 0.34
            let phase = depth * 2.1
            var fill = Path()
            var crest = Path()
            var isFirstPoint = true

            fill.move(to: CGPoint(x: -14, y: size.height + 14))

            for x in stride(
                from: CGFloat(-14),
                through: size.width + 14,
                by: 2
            ) {
                let progress = Double(x / size.width)
                let wave = sin(
                    progress * .pi * 2 * frequency
                        + time * (0.16 + depth * 0.035)
                        + phase
                )
                    + sin(
                        progress * .pi * 4.4
                            - time * (0.11 + depth * 0.022)
                            + phase * 1.7
                    ) * 0.34
                    + sin(
                        progress * .pi * 8.6
                            + time * 0.08
                            + Double(layer) * 0.9
                    ) * 0.12
                let y = baseY - CGFloat(wave) * amplitude
                let point = CGPoint(x: x, y: y)

                if isFirstPoint {
                    crest.move(to: point)
                    isFirstPoint = false
                } else {
                    crest.addLine(to: point)
                }
                fill.addLine(to: point)
            }

            fill.addLine(
                to: CGPoint(x: size.width + 14, y: size.height + 14)
            )
            fill.closeSubpath()

            let gradient = Gradient(stops: [
                .init(color: accent.opacity(0.04), location: 0),
                .init(
                    color: accent.opacity(0.10 + (1 - depth) * 0.08),
                    location: 0.34
                ),
                .init(color: accent.opacity(0.055), location: 0.70),
                .init(color: .black.opacity(0.22), location: 1)
            ])

            context.drawLayer { waveLayer in
                waveLayer.addFilter(.blur(radius: 1.1 + depth * 2.1))
                waveLayer.fill(
                    fill,
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(
                            x: 0,
                            y: baseY - amplitude * 1.5
                        ),
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )
            }

            context.drawLayer { glowLayer in
                glowLayer.blendMode = .screen
                glowLayer.addFilter(.blur(radius: 4.2 + depth * 1.8))
                glowLayer.stroke(
                    crest,
                    with: .color(accent.opacity(0.22 - depth * 0.045)),
                    style: StrokeStyle(
                        lineWidth: 3.2 + CGFloat(depth) * 1.8,
                        lineCap: .round
                    )
                )
            }

            context.drawLayer { highlightLayer in
                highlightLayer.blendMode = .screen
                highlightLayer.addFilter(.blur(radius: 0.45 + depth * 1.1))
                highlightLayer.stroke(
                    crest,
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: accent.opacity(0.18), location: 0),
                            .init(
                                color: accent.opacity(0.76 - depth * 0.20),
                                location: 0.42
                            ),
                            .init(
                                color: .white.opacity(0.50 - depth * 0.12),
                                location: 0.58
                            ),
                            .init(color: accent.opacity(0.16), location: 1)
                        ]),
                        startPoint: CGPoint(x: 0, y: baseY),
                        endPoint: CGPoint(x: size.width, y: baseY)
                    ),
                    style: StrokeStyle(
                        lineWidth: 0.82 + CGFloat(depth) * 0.92,
                        lineCap: .round
                    )
                )
            }
        }
    }
}

private struct AeroShardsBackground: View {
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: reduceMotion
            )
        ) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                drawShards(in: &context, size: size, time: time)
            }
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.28),
                    .init(color: .white.opacity(0.38), location: 0.50),
                    .init(color: .white, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawShards(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        guard size.width > 0, size.height > 0 else { return }

        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(colors: [
                    accent.opacity(0.12),
                    accent.opacity(0.035),
                    .clear
                ]),
                center: CGPoint(x: size.width * 0.54, y: size.height * 0.68),
                startRadius: 0,
                endRadius: size.width * 0.54
            )
        )

        for layer in (0..<5).reversed() {
            let depth = Double(layer) / 4
            let baseY = size.height * CGFloat(0.51 + depth * 0.085)
            let bandHeight = size.height * CGFloat(0.075 + depth * 0.035)
            let shardCount = 50 - layer * 4

            for strand in 0..<2 {
                context.drawLayer { glowLayer in
                    glowLayer.blendMode = .screen
                    glowLayer.addFilter(.blur(radius: 4.2 + depth * 2.4))

                    for index in 0..<shardCount {
                        let shard = shardGeometry(
                            layer: layer,
                            strand: strand,
                            index: index,
                            count: shardCount,
                            size: size,
                            baseY: baseY,
                            bandHeight: bandHeight,
                            time: time
                        )
                        glowLayer.fill(
                            shard.path,
                            with: .color(accent.opacity(0.085))
                        )
                    }
                }

                context.drawLayer { sharpLayer in
                    sharpLayer.blendMode = .screen
                    sharpLayer.addFilter(.blur(radius: 0.22 + depth * 0.62))

                    for index in 0..<shardCount {
                        let shard = shardGeometry(
                            layer: layer,
                            strand: strand,
                            index: index,
                            count: shardCount,
                            size: size,
                            baseY: baseY,
                            bandHeight: bandHeight,
                            time: time
                        )
                        let opacity = 0.16 + shard.shine * 0.40
                        sharpLayer.fill(
                            shard.path,
                            with: .color(accent.opacity(opacity))
                        )
                        sharpLayer.stroke(
                            shard.path,
                            with: .color(
                                Color.white.opacity(0.14 + shard.shine * 0.44)
                            ),
                            lineWidth: 0.36 + shard.shine * 0.50
                        )
                    }
                }
            }
        }

        drawMarkers(in: &context, size: size, time: time)
    }

    private func shardGeometry(
        layer: Int,
        strand: Int,
        index: Int,
        count: Int,
        size: CGSize,
        baseY: CGFloat,
        bandHeight: CGFloat,
        time: TimeInterval
    ) -> (path: Path, shine: CGFloat) {
        let depth = Double(layer) / 4
        let seedA = EffectMath.randomSeed(layer: layer, index: index)
        let seedB = EffectMath.randomSeed(
            layer: layer,
            index: index + 101
        )
        let seedC = EffectMath.randomSeed(
            layer: layer,
            index: index + 211
        )
        let speed = 0.010 + (1 - depth) * 0.006
        let progress = EffectMath.fraction(
            Double(index) / Double(count)
                + time * speed
                + Double(strand) * 0.37
                + Double(layer) * 0.11
                + (seedA - 0.5) * 0.015
        )
        let x = CGFloat(progress) * (size.width + 72) - 36
        let phase = time * (0.32 + depth * 0.08)
            + Double(index) * 0.77
            + Double(layer) * 1.13
            + Double(strand) * 2.37
        let slope = (strand == 0 ? -0.22 : 0.22)
            + (strand == 0 ? depth * 0.04 : -depth * 0.04)
        let y = baseY
            + CGFloat(slope) * (x - size.width / 2)
            + CGFloat(sin(progress * .pi * 2.4 + phase))
                * bandHeight * 0.45
            + CGFloat(seedB - 0.5) * bandHeight * 0.70
        let rotation = CGFloat(atan(slope))
            + CGFloat(sin(phase * 0.83)) * 0.20
            + CGFloat(seedC - 0.5) * 0.55
        let length = CGFloat(5 + seedB * 11)
            * CGFloat(1.22 - depth * 0.34)
        let thickness = CGFloat(0.68 + seedC * 1.72)
            * CGFloat(1.10 - depth * 0.20)
        let skew = CGFloat((seedA - 0.5) * 0.85)
        let shine = CGFloat(
            0.45 + 0.55 * (0.5 + 0.5 * sin(phase * 1.7 + seedC * 4))
        )

        return (
            shardPath(
                center: CGPoint(x: x, y: y),
                length: length,
                thickness: thickness,
                rotation: rotation,
                skew: skew
            ),
            shine
        )
    }

    private func shardPath(
        center: CGPoint,
        length: CGFloat,
        thickness: CGFloat,
        rotation: CGFloat,
        skew: CGFloat
    ) -> Path {
        let cosine = CGFloat(cos(Double(rotation)))
        let sine = CGFloat(sin(Double(rotation)))

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let skewedX = x + y * skew
            return CGPoint(
                x: center.x + skewedX * cosine - y * sine,
                y: center.y + skewedX * sine + y * cosine
            )
        }

        var path = Path()
        path.move(to: point(-length / 2, -thickness / 2))
        path.addLine(to: point(length / 2, -thickness / 2))
        path.addLine(to: point(length / 2, thickness / 2))
        path.addLine(to: point(-length / 2, thickness / 2))
        path.closeSubpath()
        return path
    }

    private func drawMarkers(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        for index in 0..<9 {
            let seed = Double(index) * 0.173 + 0.08
            let x = CGFloat(
                EffectMath.fraction(
                    seed
                        + sin(time * 0.04 + Double(index)) * 0.015
                )
            ) * size.width
            let yProgress = EffectMath.fraction(
                Double(index) * 0.317 + 0.22
            )
            let y = size.height * CGFloat(0.38 + yProgress * 0.52)
            let length = CGFloat(1.6 + Double(index % 3) * 0.7)
            let opacity = 0.16 + Double(index % 4) * 0.04
            var marker = Path()
            marker.move(to: CGPoint(x: x - length, y: y))
            marker.addLine(to: CGPoint(x: x + length, y: y))
            marker.move(to: CGPoint(x: x, y: y - length))
            marker.addLine(to: CGPoint(x: x, y: y + length))
            context.stroke(
                marker,
                with: .color(accent.opacity(opacity)),
                lineWidth: 0.55
            )
        }
    }

}

private struct AuroraGlow: View {
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: reduceMotion
            )
        ) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                context.blendMode = .screen
                context.addFilter(
                    .blur(radius: max(5, size.height * 0.055))
                )

                for layer in 0..<3 {
                    drawAuroraLayer(
                        in: &context,
                        size: size,
                        time: time,
                        layer: layer
                    )
                }
            }
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.34),
                    .init(color: .white.opacity(0.45), location: 0.56),
                    .init(color: .white, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawAuroraLayer(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval,
        layer: Int
    ) {
        guard size.width > 0, size.height > 0 else { return }

        let width = size.width
        let height = size.height
        let layerValue = Double(layer)
        let phase = layerValue * 1.65
        let baseY = height * (0.66 + CGFloat(layer) * 0.045)
        let amplitude = height * (0.135 + CGFloat(layer) * 0.018)
        var edgePath = Path()

        for x in stride(from: CGFloat(-4), through: width + 4, by: 4) {
            let progress = Double(x / width)
            let wave = sin(progress * .pi * 2.1 + time * 0.95 + phase)
                + sin(progress * .pi * 5.2 - time * 0.62 + phase * 0.7) * 0.46
                + sin(progress * .pi * 9.4 + time * 0.38 - phase * 0.35) * 0.18
            let y = baseY + CGFloat(wave) * amplitude
            let point = CGPoint(x: x, y: y)

            if x == -4 {
                edgePath.move(to: point)
            } else {
                edgePath.addLine(to: point)
            }
        }

        var fillPath = edgePath
        fillPath.addLine(to: CGPoint(x: width + 4, y: height + 4))
        fillPath.addLine(to: CGPoint(x: -4, y: height + 4))
        fillPath.closeSubpath()

        let intensity = 0.78 - layerValue * 0.16
        let gradient = Gradient(stops: [
            .init(color: accent.opacity(0.10 * intensity), location: 0),
            .init(color: accent.opacity(0.92 * intensity), location: 0.48),
            .init(color: accent.opacity(0.14 * intensity), location: 1)
        ])
        context.fill(
            fillPath,
            with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: 0, y: height),
                endPoint: CGPoint(x: width, y: height)
            )
        )

        context.stroke(
            edgePath,
            with: .color(accent.opacity(0.34 * intensity)),
            style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
        )
    }
}

private struct ProceduralNotchBackground: View {
    let effect: NotchBackgroundEffect
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct GalaxyStar {
        let center: CGPoint
        let radius: CGFloat
        let opacity: Double
        let path: Path
    }

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: reduceMotion
            )
        ) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                guard size.width > 0, size.height > 0 else { return }
                context.blendMode = .screen

                switch effect {
                case .aurora:
                    break
                case .threads:
                    drawThreads(in: &context, size: size, time: time)
                case .galaxy:
                    drawGalaxy(in: &context, size: size, time: time)
                case .gradientWaves, .aeroShards, .pixelMatrix, .spectrum,
                     .albumFlow:
                    break
                }
            }
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.30),
                    .init(color: .white.opacity(0.34), location: 0.52),
                    .init(color: .white, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawThreads(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        let width = size.width
        let height = size.height

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 0.85))

            for index in 0..<22 {
                let depth = CGFloat(index) / 21
                let baseY = height * (0.39 + depth * 0.63)
                let amplitude = height * (0.045 + depth * 0.055)
                let phase = Double(index) * 0.53
                var path = Path()

                for x in stride(from: CGFloat(-4), through: width + 4, by: 4) {
                    let progress = Double(x / width)
                    let wave = sin(progress * .pi * 3.2 + time * 0.72 + phase)
                        + sin(progress * .pi * 7.4 - time * 0.43 + phase * 0.6) * 0.34
                    let y = baseY + CGFloat(wave) * amplitude
                    let point = CGPoint(x: x, y: y)

                    if x == -4 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }

                let intensity = 0.90 - Double(depth) * 0.35
                layer.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: accent.opacity(0.09), location: 0),
                            .init(color: accent.opacity(intensity), location: 0.46),
                            .init(color: accent.opacity(0.10), location: 1)
                        ]),
                        startPoint: CGPoint(x: 0, y: baseY),
                        endPoint: CGPoint(x: width, y: baseY)
                    ),
                    style: StrokeStyle(
                        lineWidth: 0.85 + depth * 1.25,
                        lineCap: .round
                    )
                )
            }
        }

        for index in 0..<10 {
            let seed = Double(index)
            let progress = EffectMath.fraction(
                time * 0.055 + seed * 0.173
            )
            let x = CGFloat(progress) * width
            let wave = sin(progress * .pi * 3.2 + time * 0.72 + seed * 0.53)
            let y = height * 0.72 + CGFloat(wave) * height * 0.17
            let note = index.isMultiple(of: 3) ? "♫" : "♪"
            let fontSize = 11 + CGFloat(index % 3) * 1.8
            let resolvedNote = context.resolve(
                Text(note)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(accent.opacity(0.90))
            )
            context.draw(resolvedNote, at: CGPoint(x: x, y: y), anchor: .center)
        }
    }

    private func drawGalaxy(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        let width = size.width
        let height = size.height
        let stars = (0..<104).map { index -> GalaxyStar in
            let seed = Double(index)
            let fallSpeed = 0.014 + Double(index % 7) * 0.0028
            let sway = sin(time * 0.42 + seed * 1.71) * 0.018
            let xProgress = EffectMath.fraction(
                seed * 0.754877666 + 0.09 + sway
            )
            let yProgress = EffectMath.fraction(
                seed * 0.4637211 + time * fallSpeed
            )
            let center = CGPoint(
                x: CGFloat(xProgress) * width,
                y: height * (0.10 + CGFloat(yProgress) * 1.0)
            )
            let sizeSeed = EffectMath.fraction(seed * 3.173 + 0.37)
            let radius = CGFloat(0.85 + pow(sizeSeed, 1.8) * 4.6)
            let twinkle = 0.42 + pow(
                max(0, sin(time * 0.9 + seed * 1.37)),
                2
            ) * 0.58
            let variant = Int(
                EffectMath.fraction(seed * 6.917 + 2.13) * 10
            )
            let rotation =
                EffectMath.fraction(seed * 4.731 + 0.29) * .pi * 2
                + time * (0.035 + Double(index % 4) * 0.012)
            let horizontalScale = 0.62
                + CGFloat(
                    EffectMath.fraction(seed * 2.417 + 4.81)
                ) * 0.92
            let verticalScale = 0.62
                + CGFloat(
                    EffectMath.fraction(seed * 5.123 + 1.67)
                ) * 0.92
            let pinch = 0.08
                + CGFloat(
                    EffectMath.fraction(seed * 8.219 + 3.41)
                ) * 0.18
            let path: Path

            if variant == 9 || radius < 1.1 {
                let dotRadius = max(radius * 0.58, 0.65)
                path = Path(
                    ellipseIn: CGRect(
                        x: center.x - dotRadius,
                        y: center.y - dotRadius,
                        width: dotRadius * 2,
                        height: dotRadius * 2
                    )
                )
            } else {
                path = fourPointStarPath(
                    center: center,
                    horizontalRadius: radius * horizontalScale,
                    verticalRadius: radius * verticalScale,
                    pinch: pinch,
                    rotation: rotation
                )
            }

            return GalaxyStar(
                center: center,
                radius: radius,
                opacity: twinkle,
                path: path
            )
        }

        context.drawLayer { glowLayer in
            glowLayer.addFilter(.blur(radius: 4.2))

            for star in stars where star.radius > 1.5 {
                let glowRect = CGRect(
                    x: star.center.x - star.radius * 2.8,
                    y: star.center.y - star.radius * 2.8,
                    width: star.radius * 5.6,
                    height: star.radius * 5.6
                )
                glowLayer.fill(
                    Path(ellipseIn: glowRect),
                    with: .radialGradient(
                        Gradient(colors: [
                            .white.opacity(star.opacity * 0.34),
                            .white.opacity(star.opacity * 0.12),
                            .clear
                        ]),
                        center: star.center,
                        startRadius: 0,
                        endRadius: star.radius * 2.8
                    )
                )
                glowLayer.fill(
                    star.path,
                    with: .color(.white.opacity(star.opacity * 0.54))
                )
            }
        }

        context.drawLayer { sharpLayer in
            sharpLayer.addFilter(.blur(radius: 0.16))

            for star in stars {
                sharpLayer.fill(
                    star.path,
                    with: .color(.white.opacity(star.opacity))
                )
            }
        }
    }

    private func fourPointStarPath(
        center: CGPoint,
        horizontalRadius: CGFloat,
        verticalRadius: CGFloat,
        pinch: CGFloat,
        rotation: Double
    ) -> Path {
        let cosine = CGFloat(cos(rotation))
        let sine = CGFloat(sin(rotation))

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: center.x + x * cosine - y * sine,
                y: center.y + x * sine + y * cosine
            )
        }

        var path = Path()
        path.move(to: point(0, -verticalRadius))
        path.addQuadCurve(
            to: point(horizontalRadius, 0),
            control: point(
                horizontalRadius * pinch,
                -verticalRadius * pinch
            )
        )
        path.addQuadCurve(
            to: point(0, verticalRadius),
            control: point(
                horizontalRadius * pinch,
                verticalRadius * pinch
            )
        )
        path.addQuadCurve(
            to: point(-horizontalRadius, 0),
            control: point(
                -horizontalRadius * pinch,
                verticalRadius * pinch
            )
        )
        path.addQuadCurve(
            to: point(0, -verticalRadius),
            control: point(
                -horizontalRadius * pinch,
                -verticalRadius * pinch
            )
        )
        path.closeSubpath()

        return path
    }

}

struct NotchBlurTransitionModifier: ViewModifier, Animatable {
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}

struct NotchScaleTransitionModifier: ViewModifier, Animatable {
    var scale: CGFloat
    let anchor: UnitPoint

    var animatableData: CGFloat {
        get { scale }
        set { scale = newValue }
    }

    func body(content: Content) -> some View {
        content.scaleEffect(min(scale, 1.10), anchor: anchor)
    }
}

struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get {
            AnimatablePair(topCornerRadius, bottomCornerRadius)
        }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let topRadius = min(
            topCornerRadius,
            min(rect.width / 2, rect.height / 2)
        )
        let bottomRadius = min(
            bottomCornerRadius,
            min(rect.width / 2 - topRadius, rect.height / 2)
        )
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(
                x: rect.minX + topRadius,
                y: rect.minY + topRadius
            ),
            control: CGPoint(x: rect.minX + topRadius, y: rect.minY)
        )
        path.addLine(
            to: CGPoint(
                x: rect.minX + topRadius,
                y: rect.maxY - bottomRadius
            )
        )
        path.addQuadCurve(
            to: CGPoint(
                x: rect.minX + topRadius + bottomRadius,
                y: rect.maxY
            ),
            control: CGPoint(x: rect.minX + topRadius, y: rect.maxY)
        )
        path.addLine(
            to: CGPoint(
                x: rect.maxX - topRadius - bottomRadius,
                y: rect.maxY
            )
        )
        path.addQuadCurve(
            to: CGPoint(
                x: rect.maxX - topRadius,
                y: rect.maxY - bottomRadius
            ),
            control: CGPoint(x: rect.maxX - topRadius, y: rect.maxY)
        )
        path.addLine(
            to: CGPoint(
                x: rect.maxX - topRadius,
                y: rect.minY + topRadius
            )
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topRadius, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

