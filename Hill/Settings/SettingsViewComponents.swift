import SwiftUI

struct MusicSpectrumDetail: View {
    let isEnabled: Bool

    @EnvironmentObject private var audioSpectrumMonitor: AudioSpectrumMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusRow

            HStack(alignment: .top, spacing: 8) {
                Text("使用 Core Audio Process Tap 仅捕获 Apple Music。首次播放时系统会请求音频录制权限，频谱只在本机计算，不保存或上传音频。")
                    .settingsCaption()

                Spacer(minLength: 4)

                Button("隐私设置") {
                    audioSpectrumMonitor.openPrivacySettings()
                }
                .controlSize(.small)
                .disabled(!isEnabled)
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Text("频谱状态")
                .font(.system(size: 11.5, weight: .medium))

            Spacer()

            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(audioSpectrumMonitor.status.text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(statusColor)
                .multilineTextAlignment(.trailing)
        }
    }

    private var statusColor: Color {
        switch audioSpectrumMonitor.status {
        case .running:
            return .green
        case .starting:
            return .orange
        case .failed:
            return .red
        case .disabled, .waitingForPlayback:
            return .secondary
        }
    }
}

struct SettingsSidebar: View {
    @Binding var selectedCategory: SettingsCategory

    @State private var isExpanded = false
    @State private var hoveredCategory: SettingsCategory?

    var body: some View {
        VStack(spacing: 5) {
            ForEach(SettingsCategory.allCases) { category in
                button(category)
            }
        }
        .padding(6)
        .frame(
            width: isExpanded ? 172 : 52,
            alignment: .topLeading
        )
        .settingsGlassSurface(cornerRadius: 24, interactive: true)
        .animation(
            .spring(response: 0.32, dampingFraction: 0.84),
            value: isExpanded
        )
        .onHover { hovering in
            isExpanded = hovering
        }
    }

    private func button(_ category: SettingsCategory) -> some View {
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
                        width: isExpanded ? 100 : 0,
                        alignment: .leading
                    )
                    .opacity(isExpanded ? 1 : 0)
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
                width: isExpanded ? 160 : 40,
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
}

struct LightingStyleButton: View {
    let style: LightingHUDStyle
    let speed: SoundHUDSpeed
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.settingsPreviewsActive) private var previewsActive
    @State private var previewLevel: CGFloat = 1

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 5) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.14))

                        Capsule()
                            .fill(fill)
                            .frame(width: geometry.size.width)
                            .scaleEffect(
                                x: fillFraction,
                                anchor: .leading
                            )
                            .opacity(
                                style == .glow
                                    ? 0.3 + 0.7 * previewLevel
                                    : 1
                            )
                            .shadow(
                                color: glowColor.opacity(
                                    style == .glow
                                        ? 0.55 + 0.45 * previewLevel
                                        : 1
                                ),
                                radius: style == .glow ? 9 : 0
                            )
                            .shadow(
                                color: style == .glow
                                    ? Color.white.opacity(
                                        0.45 + 0.4 * previewLevel
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
        .help(style.displayName)
        .accessibilityLabel("灯光样式 \(style.displayName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .task(id: previewTaskID) {
            await runPreview()
        }
    }

    private var previewTaskID: String {
        "\(style.rawValue)-\(speed.rawValue)-\(previewsActive)-\(reduceMotion)"
    }

    private var fill: AnyShapeStyle {
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

    private var fillFraction: CGFloat {
        style == .glow ? previewLevel : 0.69
    }

    private var glowColor: Color {
        style == .glow ? Color.white.opacity(0.80) : .clear
    }

    private func runPreview() async {
        guard style == .glow, previewsActive, !reduceMotion else {
            previewLevel = 1
            return
        }

        let animation = SoundHUDAppearance.animation(
            speed: speed,
            reduceMotion: false,
            applies: true
        )
        let holdDelay: UInt64 = speed == .smooth
            ? 2_600_000_000
            : 2_000_000_000

        previewLevel = 1
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: holdDelay)
            guard !Task.isCancelled else { return }
            withAnimation(animation) {
                previewLevel = 0.64
            }
            try? await Task.sleep(nanoseconds: holdDelay)
            guard !Task.isCancelled else { return }
            withAnimation(animation) {
                previewLevel = 0.85
            }
            try? await Task.sleep(nanoseconds: holdDelay)
            guard !Task.isCancelled else { return }
            withAnimation(animation) {
                previewLevel = 1
            }
        }
    }
}

struct SoundStyleButton: View {
    let style: SoundHUDStyle
    let speed: SoundHUDSpeed
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.settingsPreviewsActive) private var previewsActive
    @State private var previewLevel: CGFloat = 0.40

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 5) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.14))

                        Capsule()
                            .fill(fill)
                            .frame(width: geometry.size.width)
                            .scaleEffect(
                                x: fillFraction,
                                anchor: .leading
                            )
                            .shadow(
                                color: glowColor,
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
        .help(style.displayName)
        .accessibilityLabel("声音样式 \(style.displayName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .task(id: previewTaskID) {
            await runPreview()
        }
    }

    private var previewTaskID: String {
        "\(style.rawValue)-\(speed.rawValue)-\(previewsActive)-\(reduceMotion)"
    }

    private var previewColor: Color {
        SoundHUDAppearance.decibelColor(for: previewLevel)
    }

    private var fill: AnyShapeStyle {
        switch style {
        case .white:
            return AnyShapeStyle(Color.white)
        case .accent:
            return AnyShapeStyle(Color.accentColor)
        case .decibel:
            return AnyShapeStyle(previewColor)
        }
    }

    private var glowColor: Color {
        style == .decibel ? previewColor.opacity(0.55) : .clear
    }

    private var fillFraction: CGFloat {
        style == .decibel ? previewLevel : 0.69
    }

    private func runPreview() async {
        guard style == .decibel, previewsActive else {
            previewLevel = 0.40
            return
        }

        let animation = SoundHUDAppearance.animation(
            speed: speed,
            reduceMotion: reduceMotion,
            applies: true
        )
        let stepDelay: UInt64 = speed == .smooth
            ? 800_000_000
            : 450_000_000
        let edgeDelay: UInt64 = speed == .smooth
            ? 1_600_000_000
            : 1_000_000_000
        let levels: [CGFloat] = [
            0.40, 0.50, 0.60, 0.70, 0.80, 0.90, 1.0
        ]

        previewLevel = levels[0]
        while !Task.isCancelled {
            for level in levels.dropFirst() {
                guard !Task.isCancelled else { return }
                withAnimation(animation) {
                    previewLevel = level
                }
                try? await Task.sleep(nanoseconds: stepDelay)
            }
            guard !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: edgeDelay)
            for level in levels.dropLast().reversed() {
                guard !Task.isCancelled else { return }
                withAnimation(animation) {
                    previewLevel = level
                }
                try? await Task.sleep(nanoseconds: stepDelay)
            }
            guard !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: edgeDelay)
        }
    }
}

struct SettingsPageTabs: View {
    let titles: [String]
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                Button {
                    onSelect(index)
                } label: {
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(
                            index == selectedIndex
                                ? Color.white
                                : Color.primary.opacity(0.62)
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background {
            GeometryReader { proxy in
                let segmentWidth = max(proxy.size.width - 6, 0)
                    / CGFloat(max(titles.count, 1))

                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.accentColor.opacity(0.78))
                    .frame(
                        width: segmentWidth,
                        height: max(proxy.size.height - 6, 0)
                    )
                    .offset(
                        x: CGFloat(selectedIndex) * segmentWidth + 3,
                        y: 3
                    )
            }
            .allowsHitTesting(false)
        }
        .background(
            Color.primary.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    Color.primary.opacity(0.08),
                    lineWidth: 0.8
                )
        }
        .animation(
            .easeInOut(duration: 0.45),
            value: selectedIndex
        )
    }
}

struct SparklesText: View {
    let text: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.settingsPreviewsActive) private var previewsActive
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
                    .id(previewsActive)
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

    @Environment(\.settingsPreviewsActive) private var previewsActive
    @State private var isVisible = false

    var body: some View {
        SparkleShape()
            .fill(sparkle.color)
            .frame(width: 13, height: 13)
            .scaleEffect(isVisible ? sparkle.scale : 0.001)
            .opacity(isVisible ? 1 : 0)
            .rotationEffect(.degrees(isVisible ? 150 : 75))
            .animation(
                previewsActive
                    ? .easeInOut(duration: 0.4)
                        .repeatForever(autoreverses: true)
                        .delay(sparkle.delay)
                    : nil,
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

struct ConfettiLayer: View {
    let startDate: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isFinished = false

    private let duration: TimeInterval = 4.0
    private let fadeDuration: TimeInterval = 0.8

    var body: some View {
        Group {
            if reduceMotion || isFinished {
                Color.clear
            } else {
                TimelineView(
                    .animation(minimumInterval: NotchTiming.thirtyFPS)
                ) { timeline in
                    let elapsed = timeline.date.timeIntervalSince(startDate)

                    if elapsed >= duration {
                        Color.clear
                    } else {
                        ConfettiCanvas(time: elapsed)
                            .opacity(
                                max(0, min(1, (duration - elapsed) / fadeDuration))
                            )
                    }
                }
            }
        }
        .onAppear {
            if Date().timeIntervalSince(startDate) >= duration {
                isFinished = true
            }
        }
        .task(id: startDate) {
            let remaining = duration - Date().timeIntervalSince(startDate)
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
            }
            isFinished = true
        }
    }
}

private struct ConfettiCanvas: View {
    let time: TimeInterval

    private let particleCount = 48

    private let palette = [
        Color(red: 1.00, green: 0.42, blue: 0.34),
        Color(red: 1.00, green: 0.55, blue: 0.73),
        Color(red: 0.62, green: 0.48, blue: 1.00),
        Color(red: 1.00, green: 0.80, blue: 0.45),
        Color(red: 0.45, green: 0.80, blue: 0.70),
        Color(red: 0.42, green: 0.80, blue: 0.62),
        Color(red: 0.42, green: 0.66, blue: 1.00)
    ]

    var body: some View {
        Canvas { context, size in
            guard size.width > 120, size.height > 120 else { return }
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
        let phase = Double(unitRandom(index, 1))
        let speed = 46 + 54 * Double(unitRandom(index, 2))
        let startX =
            Double(size.width) * (0.02 + 0.96 * Double(unitRandom(index, 3)))
        let swayAmplitude = 4 + 12 * Double(unitRandom(index, 4))
        let swaySpeed = 0.22 + 0.45 * Double(unitRandom(index, 5))
        let drift = (Double(unitRandom(index, 6)) - 0.5) * 12
        let baseRotation = 360 * Double(unitRandom(index, 7))
        let spinSpeed = (Double(unitRandom(index, 8)) - 0.5) * 70
        let flutterAmplitude = 8 + 22 * Double(unitRandom(index, 9))
        let flutterSpeed = 0.55 + 1.0 * Double(unitRandom(index, 10))
        let flipSpeed = 0.8 + 1.8 * Double(unitRandom(index, 11))
        let flipPhase = 6.28 * Double(unitRandom(index, 12))
        let width = 1.8 + 1.8 * Double(unitRandom(index, 13))
        let height = 7 + 6 * Double(unitRandom(index, 14))
        let opacity = 0.7 + 0.3 * Double(unitRandom(index, 15))

        let topBand = 80.0
        let bottomBand = 24.0
        let travel = Double(size.height) + topBand + bottomBand
        let distance = (time * speed + phase * travel)
            .truncatingRemainder(dividingBy: travel)
        let y = -topBand + distance
        let elapsed = distance / speed
        let clock = time

        let sway =
            sin(clock * swaySpeed * 2 * .pi + phase * 6.28)
                * swayAmplitude
            + sin(clock * swaySpeed * 3.7 * .pi + phase * 3.1)
                * swayAmplitude * 0.22
        let x = startX + sway + drift * elapsed

        let rotation =
            baseRotation + spinSpeed * clock
            + sin(clock * flutterSpeed * 2 * .pi + phase * 6.28)
                * flutterAmplitude
        let flip =
            0.18 + 0.82 * abs(cos(clock * flipSpeed * 2 * .pi + flipPhase))

        let color = palette[index % palette.count]

        var particle = context
        particle.translateBy(x: CGFloat(x), y: CGFloat(y))
        particle.rotate(by: .degrees(rotation))
        particle.scaleBy(x: CGFloat(flip), y: 1)
        particle.fill(
            Path(
                roundedRect: CGRect(
                    x: -width / 2,
                    y: -height / 2,
                    width: width,
                    height: height
                ),
                cornerRadius: 0.8
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

}

struct SoundIconPreview: View {
    let content: SoundHUDContent

    @Environment(\.settingsPreviewsActive) private var previewsActive
    @State private var index = 0

    var body: some View {
        Group {
            if content == .symbol {
                SoundSymbolCarousel(size: 22, index: index)
            } else {
                SoundDeviceIconCarousel(size: 32, index: index)
            }
        }
        .task(id: previewsActive) {
            guard previewsActive else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                index = (index + 1) % 4
            }
        }
    }
}

private struct SoundDeviceIconCarousel: View {
    let size: CGFloat
    let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.settingsPreviewsActive) private var previewsActive

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
            if index % (models.count + 1) == models.count {
                Image(systemName: "speaker.2.fill")
                    .font(.system(size: size * 0.68, weight: .semibold))
                    .foregroundStyle(.white)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.74, anchor: .center)
                                .combined(with: .opacity),
                            removal: .scale(scale: 0.86, anchor: .center)
                                .combined(with: .opacity)
                        )
                    )
                    .allowsHitTesting(false)
            } else if !models.isEmpty {
                let model = models[index % models.count]
                AirPods3DView(
                    model: model,
                    framesPerSecond: 30,
                    isActive: previewsActive && !reduceMotion
                )
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
        return ordered.map(\.systemImage) + ["speaker.2.fill"]
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

