import SwiftUI

struct SettingsBackdrop: View {
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
                .fill(
                    RadialGradient(
                        colors: [
                            Color(
                                red: 1.0,
                                green: 0.36,
                                blue: 0.25
                            ).opacity(0.18),
                            Color(
                                red: 1.0,
                                green: 0.36,
                                blue: 0.25
                            ).opacity(0.16),
                            Color(
                                red: 1.0,
                                green: 0.36,
                                blue: 0.25
                            ).opacity(0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 165
                    )
                )
                .frame(width: 330, height: 330)
                .offset(x: -170, y: -150)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(
                                red: 0.26,
                                green: 0.66,
                                blue: 0.78
                            ).opacity(0.14),
                            Color(
                                red: 0.26,
                                green: 0.66,
                                blue: 0.78
                            ).opacity(0.12),
                            Color(
                                red: 0.26,
                                green: 0.66,
                                blue: 0.78
                            ).opacity(0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 150
                    )
                )
                .frame(width: 300, height: 300)
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

struct SystemHUDPreview: View {
    let style: SystemHUDStyle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.settingsPreviewsActive) private var previewsActive
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
        .task(id: "\(reduceMotion)-\(previewsActive)") {
            guard !reduceMotion, previewsActive else { return }
            let levels: [Double] = [0.34, 0.58, 0.82, 0.66, 0.95, 0.42]
            while !Task.isCancelled {
                for value in levels {
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        level = value
                    }
                    try? await Task.sleep(nanoseconds: 1_600_000_000)
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
                    .frame(width: proxy.size.width)
                    .scaleEffect(
                        x: CGFloat(
                            max(
                                Double(
                                    height / max(proxy.size.width, 1)
                                ),
                                level
                            )
                        ),
                        anchor: .leading
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

private struct SettingsSelectionCardModifier: ViewModifier {
    let isSelected: Bool
    let cornerRadius: CGFloat
    let selectedFillOpacity: Double
    let unselectedFillOpacity: Double
    let selectedBorderOpacity: Double
    let selectedBorderWidth: CGFloat
    let unselectedBorderWidth: CGFloat

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .background(
                isSelected
                    ? Color.accentColor.opacity(selectedFillOpacity)
                    : Color.primary.opacity(unselectedFillOpacity),
                in: shape
            )
            .overlay {
                shape.strokeBorder(
                    isSelected
                        ? Color.accentColor.opacity(selectedBorderOpacity)
                        : Color.primary.opacity(0.08),
                    lineWidth: isSelected
                        ? selectedBorderWidth
                        : unselectedBorderWidth
                )
            }
    }
}

extension View {
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

    func settingsSelectionCard(
        isSelected: Bool,
        cornerRadius: CGFloat,
        selectedFillOpacity: Double = 0.14,
        unselectedFillOpacity: Double = 0.035,
        selectedBorderOpacity: Double = 0.62,
        selectedBorderWidth: CGFloat = 1.2,
        unselectedBorderWidth: CGFloat = 0.8
    ) -> some View {
        modifier(
            SettingsSelectionCardModifier(
                isSelected: isSelected,
                cornerRadius: cornerRadius,
                selectedFillOpacity: selectedFillOpacity,
                unselectedFillOpacity: unselectedFillOpacity,
                selectedBorderOpacity: selectedBorderOpacity,
                selectedBorderWidth: selectedBorderWidth,
                unselectedBorderWidth: unselectedBorderWidth
            )
        )
    }
}
