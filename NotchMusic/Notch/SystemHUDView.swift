import SwiftUI

struct NotchSideSystemHUDView: View {
    let presentation: SystemHUDPresentation
    let albumAccent: Color
    let notchWidth: CGFloat

    @AppStorage(SystemHUDSettings.coloredVolumeEnabled)
    private var usesColoredVolume = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var color: Color {
        switch presentation.control {
        case .volume:
            return usesColoredVolume ? albumAccent : .white
        case .displayBrightness:
            return Color(red: 1.0, green: 0.88, blue: 0.56)
        case .keyboardBrightness:
            return Color(red: 0.48, green: 0.76, blue: 1.0)
        }
    }

    private var percentage: Int {
        Int((presentation.level * 100).rounded())
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(
                    systemName: presentation.control.symbolName(
                        level: presentation.level,
                        isMuted: presentation.isMuted
                    )
                )
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)

                Text(presentation.control.title)
                    .font(
                        .system(
                            size: 10.5,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                if presentation.isFineAdjustment {
                    Text("微调")
                        .font(
                            .system(
                                size: 8,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.15), in: Capsule())
                }
            }

            Spacer(minLength: notchWidth)

            HStack(spacing: 6) {
                progressBar

                Text("\(percentage)")
                    .font(
                        .system(
                            size: 10.5,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .frame(width: 18, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .spring(response: 0.26, dampingFraction: 0.82),
            value: presentation
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.control.title)
        .accessibilityValue("\(percentage)%")
    }

    private var progressBar: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(.white.opacity(0.24))

            Capsule()
                .fill(color)
                .frame(width: max(4, 62 * presentation.level))
        }
        .frame(width: 62, height: 4)
    }
}

struct SystemHUDView: View {
    let presentation: SystemHUDPresentation
    let style: SystemHUDStyle
    let albumAccent: Color

    @AppStorage(SystemHUDSettings.coloredVolumeEnabled)
    private var usesColoredVolume = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var color: Color {
        switch presentation.control {
        case .volume:
            return usesColoredVolume ? albumAccent : .white
        case .displayBrightness:
            return Color(red: 1.0, green: 0.88, blue: 0.56)
        case .keyboardBrightness:
            return Color(red: 0.48, green: 0.76, blue: 1.0)
        }
    }

    private var percentage: Int {
        Int((presentation.level * 100).rounded())
    }

    var body: some View {
        Group {
            switch style {
            case .island:
                island
            case .customOSD:
                customOSD
            case .vertical:
                vertical
            case .circular:
                circular
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .spring(response: 0.26, dampingFraction: 0.82),
            value: presentation
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.control.title)
        .accessibilityValue("\(percentage)%")
    }

    private var island: some View {
        HStack(spacing: 12) {
            iconBadge(size: 38)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(presentation.control.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))

                    if presentation.isFineAdjustment {
                        fineBadge
                    }

                    Spacer()

                    Text("\(percentage)%")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }

                horizontalProgress(height: 5)
            }
        }
        .padding(.horizontal, 16)
        .frame(width: 372, height: 70)
        .background(
            Color.black.opacity(0.46),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 0.7)
        }
    }

    private var customOSD: some View {
        HStack(spacing: 16) {
            iconBadge(size: 52)

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(presentation.control.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    if presentation.isFineAdjustment {
                        fineBadge
                    }

                    Spacer()

                    Text("\(percentage)%")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(color)
                        .contentTransition(.numericText())
                }

                horizontalProgress(height: 7)

                Text(statusText)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
        .padding(.horizontal, 18)
        .frame(width: 320, height: 108)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.8)
        }
    }

    private var vertical: some View {
        VStack(spacing: 10) {
            Image(
                systemName: presentation.control.symbolName(
                    level: presentation.level,
                    isMuted: presentation.isMuted
                )
            )
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(color)

            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(.white.opacity(0.14))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.58), color],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(height: max(7, 70 * presentation.level))
            }
            .frame(width: 9, height: 70)
            .clipShape(Capsule())

            Text("\(percentage)%")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
        .padding(.vertical, 13)
        .frame(width: 66, height: 132)
        .background(
            Color.black.opacity(0.50),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(.white.opacity(0.11), lineWidth: 0.7)
        }
    }

    private var circular: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.13), lineWidth: 9)

            Circle()
                .trim(from: 0, to: presentation.level)
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.60), color, color],
                        center: .center
                    ),
                    style: StrokeStyle(
                        lineWidth: 9,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 4) {
                Image(
                    systemName: presentation.control.symbolName(
                        level: presentation.level,
                        isMuted: presentation.isMuted
                    )
                )
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)

                Text("\(percentage)%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
        }
        .frame(width: 108, height: 108)
        .padding(8)
        .background(
            Color.black.opacity(0.34),
            in: Circle()
        )
        .overlay(alignment: .bottom) {
            if presentation.isFineAdjustment {
                fineBadge
                    .offset(y: 9)
            }
        }
    }

    private func iconBadge(size: CGFloat) -> some View {
        Image(
            systemName: presentation.control.symbolName(
                level: presentation.level,
                isMuted: presentation.isMuted
            )
        )
        .font(.system(size: size * 0.38, weight: .semibold))
        .foregroundStyle(color)
        .frame(width: size, height: size)
        .background(color.opacity(0.14), in: Circle())
        .overlay {
            Circle()
                .strokeBorder(color.opacity(0.22), lineWidth: 0.7)
        }
    }

    private func horizontalProgress(height: CGFloat) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.14))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.66), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: max(
                            height,
                            geometry.size.width * presentation.level
                        )
                    )
            }
        }
        .frame(height: height)
    }

    private var fineBadge: some View {
        Text("微调")
            .font(.system(size: 8.5, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }

    private var statusText: String {
        if presentation.isMuted {
            return "已静音"
        }
        if presentation.isFineAdjustment {
            return "精细调节"
        }
        switch presentation.control {
        case .volume:
            return "系统输出音量"
        case .displayBrightness:
            return "内建显示器亮度"
        case .keyboardBrightness:
            return "内建键盘背光"
        }
    }
}
