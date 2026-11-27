import SwiftUI

struct OverflowMarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    var speed: CGFloat = 28
    var gap: CGFloat = 36

    @State private var textWidth: CGFloat = 0
    @State private var startDate = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .foregroundStyle(.clear)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    marqueeContent(containerWidth: geometry.size.width)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .onChange(of: text) { _, _ in
                startDate = Date()
            }
    }

    private func marqueeContent(containerWidth: CGFloat) -> some View {
        let shouldScroll =
            textWidth > containerWidth + 0.5 && !reduceMotion

        return ZStack(alignment: .leading) {
            if shouldScroll {
                TimelineView(
                    .animation(minimumInterval: NotchTiming.thirtyFPS)
                ) { timeline in
                    HStack(spacing: gap) {
                        scrollingTextView
                        scrollingTextView
                    }
                    .offset(
                        x: -marqueeOffset(
                            at: timeline.date,
                            distance: textWidth + gap
                        )
                    )
                }
                .frame(width: containerWidth, alignment: .leading)
                .clipped()
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0),
                            .init(color: .white, location: 0.9),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            } else {
                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: containerWidth, alignment: .leading)
                    .clipped()
            }

            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .hidden()
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: MarqueeTextWidthKey.self,
                            value: geometry.size.width
                        )
                    }
                }
        }
        .frame(width: containerWidth, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .leading)
        .clipped()
        .onPreferenceChange(MarqueeTextWidthKey.self) { width in
            if abs(textWidth - width) > 0.5 {
                textWidth = width
            }
        }
    }

    private var scrollingTextView: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func marqueeOffset(at date: Date, distance: CGFloat) -> CGFloat {
        guard distance > 0, speed > 0 else { return 0 }

        let elapsed = max(0, date.timeIntervalSince(startDate))
        let travelDuration = Double(distance / speed)
        guard travelDuration > 0 else { return 0 }

        let holdDuration = 1.2
        let cycleDuration = travelDuration + holdDuration
        let phase = elapsed.truncatingRemainder(
            dividingBy: cycleDuration
        )
        guard phase > holdDuration else { return 0 }

        let progress = min((phase - holdDuration) / travelDuration, 1)
        return distance * CGFloat(progress)
    }
}

private struct MarqueeTextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct AccentProgressSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let color: Color
    let style: ProgressTrackStyle
    let isPlaying: Bool
    let isEnabled: Bool
    let onChange: (Double) -> Void
    let onEditingStarted: () -> Void
    let onCommit: (Double) -> Void

    @State private var isEditing = false
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let thumbSize: CGFloat = 14
    private var trackHeight: CGFloat {
        style == .softAurora ? 10 : 5
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let usableWidth = max(width - thumbSize, 0)
            let fraction = valueFraction
            let thumbOffset = usableWidth * fraction
            let filledWidth = style == .classic
                ? thumbOffset + thumbSize / 2
                : width * fraction
            let isActive = isHovering || isEditing

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(
                        style == .classic
                            ? Color.black.opacity(0.24)
                            : Color.clear
                    )
                    .frame(height: trackHeight)
                    .overlay {
                        if style == .classic {
                            Capsule()
                                .strokeBorder(
                                    Color.white.opacity(0.16),
                                    lineWidth: 0.55
                                )
                        }
                    }

                if style == .classic {
                    classicFilledTrack
                        .frame(width: filledWidth, height: trackHeight)
                        .clipShape(Capsule())
                        .shadow(
                            color: color.opacity(isActive ? 0.48 : 0.3),
                            radius: isActive ? 6 : 3,
                            y: 1
                        )
                } else {
                    SoftAuroraProgressTrack(
                        color: color,
                        isPlaying: isPlaying,
                        isActive: isActive
                    )
                    .frame(width: width, height: trackHeight)
                    .mask {
                        Rectangle()
                            .frame(width: filledWidth, height: trackHeight)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .shadow(
                        color: color.opacity(isActive ? 0.48 : 0.3),
                        radius: isActive ? 6 : 3,
                        y: 1
                    )
                }

                if isPlaying {
                    ProgressParticleBurst(
                        color: color,
                        anchorX: thumbOffset + thumbSize / 2,
                        isActive: isActive,
                        isEnabled: isEnabled
                    )
                    .frame(width: width, height: 22)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }

                if style == .classic {
                    ZStack {
                        Circle()
                            .fill(color.opacity(isActive ? 0.4 : 0.26))
                            .frame(width: thumbSize + 9, height: thumbSize + 9)
                            .blur(radius: isActive ? 4 : 3)

                        Circle()
                            .fill(color)
                            .frame(width: thumbSize - 2, height: thumbSize - 2)
                            .overlay {
                                Circle()
                                    .strokeBorder(
                                        Color.white.opacity(
                                            isActive ? 0.96 : 0.82
                                        ),
                                        lineWidth: 1.2
                                    )
                            }
                            .overlay(alignment: .topLeading) {
                                Circle()
                                    .fill(Color.white.opacity(0.72))
                                    .frame(width: 3.2, height: 3.2)
                                    .offset(x: 3.2, y: 2.5)
                            }
                            .shadow(
                                color: .black.opacity(0.42),
                                radius: 3,
                                y: 1.2
                            )
                    }
                    .scaleEffect(isActive ? 1.12 : 1)
                    .offset(x: thumbOffset)
                }
            }
            .frame(width: width, height: thumbSize)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
            }
            .animation(
                reduceMotion
                    ? nil
                    : .easeOut(duration: 0.16),
                value: isHovering
            )
            .animation(
                reduceMotion
                    ? nil
                    : .spring(response: 0.24, dampingFraction: 0.78),
                value: isEditing
            )
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

    private var classicFilledTrack: some View {
        ZStack(alignment: .topLeading) {
            Capsule()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(
                                color: color.opacity(0.58),
                                location: 0
                            ),
                            .init(color: color, location: 0.58),
                            .init(
                                color: color.opacity(0.82),
                                location: 1
                            )
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.32),
                            Color.white.opacity(0.04),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1.2)
                .padding(.horizontal, 3)
                .padding(.top, 1.1)
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

struct SoftAuroraProgressTrack: View {
    let color: Color
    let isPlaying: Bool
    let isActive: Bool

    @State private var frozenTime: TimeInterval?
    @State private var resumedAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: NotchTiming.thirtyFPS,
                paused: reduceMotion || !isPlaying
            )
        ) { timeline in
            Canvas { context, size in
                guard size.width > 0, size.height > 0 else { return }
                let time = effectiveTime(at: timeline.date)

                let ribbons: [(phase: Double, baseline: CGFloat, amplitude: CGFloat, alpha: Double)] = [
                    (
                        phase: time * 0.72,
                        baseline: 0.30,
                        amplitude: 0.20,
                        alpha: 0.62
                    ),
                    (
                        phase: time * 0.48 + 2.1,
                        baseline: 0.5,
                        amplitude: 0.27,
                        alpha: 0.78
                    ),
                    (
                        phase: -time * 0.36 + 4.3,
                        baseline: 0.70,
                        amplitude: 0.18,
                        alpha: 0.52
                    )
                ]
                let waves = ribbons.map { ribbon in
                    wavePoints(
                        size: size,
                        phase: ribbon.phase,
                        baseline: size.height * ribbon.baseline,
                        amplitude: size.height * ribbon.amplitude
                    )
                }

                context.drawLayer { glow in
                    glow.addFilter(.blur(radius: isActive ? 2.8 : 2.1))

                    for (index, points) in waves.enumerated() {
                        glow.stroke(
                            crestPath(points: points),
                            with: .color(
                                color.opacity(ribbons[index].alpha * 0.84)
                            ),
                            lineWidth: index == 1 ? 1.7 : 1.25
                        )
                    }
                }

                for (index, points) in waves.enumerated() {
                    context.stroke(
                        crestPath(points: points),
                        with: .linearGradient(
                            Gradient(
                                colors: [
                                    color.opacity(ribbons[index].alpha * 0.66),
                                    Color.white.opacity(
                                        ribbons[index].alpha * 0.52
                                    ),
                                    color.opacity(ribbons[index].alpha),
                                    Color.white.opacity(
                                        ribbons[index].alpha * 0.58
                                    ),
                                    color.opacity(ribbons[index].alpha * 0.7)
                                ]
                            ),
                            startPoint: CGPoint(x: 0, y: 0),
                            endPoint: CGPoint(x: size.width, y: 0)
                        ),
                        lineWidth: index == 1 ? 0.9 : 0.65
                    )
                }
            }
        }
        .onChange(of: isPlaying) { _, playing in
            updateTimelineState(isPlaying: playing)
        }
    }

    private func updateTimelineState(isPlaying: Bool) {
        let now = Date()
        if isPlaying {
            if frozenTime != nil {
                resumedAt = now
            }
        } else {
            frozenTime = effectiveTime(at: now)
            resumedAt = nil
        }
    }

    private func effectiveTime(at date: Date) -> TimeInterval {
        if let frozenTime, let resumedAt {
            return frozenTime + date.timeIntervalSince(resumedAt)
        }
        if let frozenTime {
            return frozenTime
        }
        return date.timeIntervalSinceReferenceDate
    }

    private func wavePoints(
        size: CGSize,
        phase: Double,
        baseline: CGFloat,
        amplitude: CGFloat
    ) -> [CGPoint] {
        let step = max(size.width / 32, 2)
        var points: [CGPoint] = []
        var x: CGFloat = -8

        while x <= size.width + 8 {
            let progress = Double(x / max(size.width, 1))
            let primary = sin(progress * .pi * 2.1 + phase) * Double(amplitude)
            let detail = sin(progress * .pi * 5.4 - phase * 0.64)
                * Double(amplitude) * 0.32
            points.append(
                CGPoint(
                    x: x,
                    y: baseline + CGFloat(primary + detail)
                )
            )
            x += step
        }

        return points
    }

    private func crestPath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }

        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }
}

private struct ProgressParticleBurst: View {
    let color: Color
    let anchorX: CGFloat
    let isActive: Bool
    let isEnabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: NotchTiming.thirtyFPS,
                paused: reduceMotion || !isEnabled
            )
        ) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let particleCount = isActive ? 34 : 20
                let center = CGPoint(x: anchorX, y: size.height / 2)
                var particles: [(center: CGPoint, radius: CGFloat, opacity: Double)] = []

                for index in 0..<particleCount {
                    let seed = Double(index)
                    let phase = EffectMath.fraction(
                        time * (isActive ? 0.68 : 0.36)
                            + seed * 0.173
                    )
                    let angle = seed * 2.399
                        + sin(time * 0.7 + seed * 0.83) * 0.42
                    let spread = CGFloat(
                        5 + phase * (isActive ? 24 : 16)
                    )
                    let x = center.x + CGFloat(cos(angle)) * spread
                    let y = center.y + CGFloat(sin(angle)) * spread * 0.72
                    guard x > -2, x < size.width + 2 else { continue }

                    let fade = sin(phase * .pi)
                    let radius = CGFloat(
                        0.65
                            + (1 - phase) * (isActive ? 1.65 : 1.1)
                    )
                    let opacity = (isActive ? 0.92 : 0.62) * fade
                    particles.append(
                        (
                            center: CGPoint(x: x, y: y),
                            radius: radius,
                            opacity: opacity
                        )
                    )
                }

                context.drawLayer { glow in
                    glow.addFilter(.blur(radius: 1.7))

                    for particle in particles {
                        let radius = particle.radius * 2
                        glow.fill(
                            Path(
                                ellipseIn: CGRect(
                                    x: particle.center.x - radius,
                                    y: particle.center.y - radius,
                                    width: radius * 2,
                                    height: radius * 2
                                )
                            ),
                            with: .color(
                                color.opacity(particle.opacity * 0.34)
                            )
                        )
                    }
                }

                for particle in particles {
                    let radius = particle.radius
                    context.fill(
                        Path(
                            ellipseIn: CGRect(
                                x: particle.center.x - radius,
                                y: particle.center.y - radius,
                                width: radius * 2,
                                height: radius * 2
                            )
                        ),
                        with: .color(color.opacity(particle.opacity))
                    )

                    let coreRadius = radius * 0.34
                    context.fill(
                        Path(
                            ellipseIn: CGRect(
                                x: particle.center.x - coreRadius,
                                y: particle.center.y - coreRadius,
                                width: coreRadius * 2,
                                height: coreRadius * 2
                            )
                        ),
                        with: .color(
                            .white.opacity(particle.opacity * 0.48)
                        )
                    )
                }
            }
        }
    }

}

