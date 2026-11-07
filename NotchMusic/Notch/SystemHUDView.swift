import SwiftUI

struct NotchSideSystemHUDView: View {
    let presentation: SystemHUDPresentation
    let albumAccent: Color
    let notchWidth: CGFloat

    @AppStorage(SoundHUDSettings.style)
    private var soundStyleRaw = SoundHUDStyle.decibel.rawValue
    @AppStorage(SoundHUDSettings.speed)
    private var soundSpeedRaw = SoundHUDSpeed.smooth.rawValue
    @AppStorage(SoundHUDSettings.showsPercentage)
    private var showsSoundPercentage = true
    @AppStorage(SoundHUDSettings.hidesLabel)
    private var hidesSoundLabel = false
    @AppStorage(SoundHUDSettings.content)
    private var soundContentRaw = SoundHUDContent.device.rawValue
    @AppStorage(LightingHUDSettings.style)
    private var lightingStyleRaw = LightingHUDStyle.glow.rawValue
    @AppStorage(LightingHUDSettings.speed)
    private var lightingSpeedRaw = SoundHUDSpeed.smooth.rawValue
    @AppStorage(LightingHUDSettings.showsPercentage)
    private var showsLightingPercentage = true
    @AppStorage(LightingHUDSettings.hidesLabel)
    private var hidesLightingLabel = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var soundStyle: SoundHUDStyle {
        SoundHUDStyle(rawValue: soundStyleRaw) ?? .decibel
    }

    private var soundSpeed: SoundHUDSpeed {
        SoundHUDSpeed(rawValue: soundSpeedRaw) ?? .smooth
    }

    private var soundContent: SoundHUDContent {
        SoundHUDContent(rawValue: soundContentRaw) ?? .device
    }

    private var lightingStyle: LightingHUDStyle {
        LightingHUDStyle(rawValue: lightingStyleRaw) ?? .glow
    }

    private var lightingSpeed: SoundHUDSpeed {
        SoundHUDSpeed(rawValue: lightingSpeedRaw) ?? .smooth
    }

    private var color: Color {
        switch presentation.control {
        case .volume:
            return SoundHUDAppearance.color(
                for: soundStyle,
                accent: albumAccent,
                level: presentation.level
            )
        case .displayBrightness, .keyboardBrightness:
            return SoundHUDAppearance.lightingColor(
                for: lightingStyle,
                control: presentation.control
            )
        }
    }

    private var showsPercentage: Bool {
        presentation.control == .volume
            ? showsSoundPercentage
            : showsLightingPercentage
    }

    private var hidesLabel: Bool {
        presentation.control == .volume
            ? hidesSoundLabel
            : hidesLightingLabel
    }

    private var presentationAnimation: Animation? {
        SoundHUDAppearance.animation(
            speed: presentation.control == .volume
                ? soundSpeed
                : lightingSpeed,
            reduceMotion: reduceMotion,
            applies: true
        )
    }

    private var percentage: Int {
        Int((presentation.level * 100).rounded())
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                SoundHUDIcon(
                    control: presentation.control,
                    content: soundContent,
                    level: presentation.level,
                    isMuted: presentation.isMuted,
                    color: color,
                    size: 22,
                    symbolScale: 0.55
                )

                if !hidesLabel {
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
                }

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

                if showsPercentage {
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
                        .frame(width: 26, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(presentationAnimation, value: presentation)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.control.title)
        .accessibilityValue("\(percentage)%")
    }

    private var progressBar: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(.white.opacity(0.24))

            if presentation.level > 0 {
                Capsule()
                    .fill(progressFill)
                    .frame(width: max(4, 62 * presentation.level))
                    .shadow(
                        color: presentation.control == .volume
                            ? SoundHUDAppearance.glow(
                                for: soundStyle,
                                accent: albumAccent,
                                level: presentation.level,
                                applies: true
                            )
                            : SoundHUDAppearance.lightingGlow(
                                for: lightingStyle,
                                control: presentation.control
                            ),
                        radius: presentation.control == .volume
                            ? 5
                            : SoundHUDAppearance.lightingGlowRadius(
                                for: lightingStyle
                            )
                    )
                    .shadow(
                        color: presentation.control == .volume
                            ? .clear
                            : SoundHUDAppearance.lightingCoreGlow(
                                for: lightingStyle
                            ),
                        radius: 2
                    )
            }
        }
        .frame(width: 62, height: 4)
    }

    private var progressFill: AnyShapeStyle {
        presentation.control != .volume && lightingStyle == .glow
            ? SoundHUDAppearance.lightingBeamStyle(vertical: false)
            : AnyShapeStyle(color)
    }
}

struct SystemHUDView: View {
    let presentation: SystemHUDPresentation
    let style: SystemHUDStyle
    let albumAccent: Color

    @AppStorage(SoundHUDSettings.style)
    private var soundStyleRaw = SoundHUDStyle.decibel.rawValue
    @AppStorage(SoundHUDSettings.speed)
    private var soundSpeedRaw = SoundHUDSpeed.smooth.rawValue
    @AppStorage(SoundHUDSettings.showsPercentage)
    private var showsSoundPercentage = true
    @AppStorage(SoundHUDSettings.hidesLabel)
    private var hidesSoundLabel = false
    @AppStorage(SoundHUDSettings.content)
    private var soundContentRaw = SoundHUDContent.device.rawValue
    @AppStorage(LightingHUDSettings.style)
    private var lightingStyleRaw = LightingHUDStyle.glow.rawValue
    @AppStorage(LightingHUDSettings.speed)
    private var lightingSpeedRaw = SoundHUDSpeed.smooth.rawValue
    @AppStorage(LightingHUDSettings.showsPercentage)
    private var showsLightingPercentage = true
    @AppStorage(LightingHUDSettings.hidesLabel)
    private var hidesLightingLabel = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var soundStyle: SoundHUDStyle {
        SoundHUDStyle(rawValue: soundStyleRaw) ?? .decibel
    }

    private var soundSpeed: SoundHUDSpeed {
        SoundHUDSpeed(rawValue: soundSpeedRaw) ?? .smooth
    }

    private var soundContent: SoundHUDContent {
        SoundHUDContent(rawValue: soundContentRaw) ?? .device
    }

    private var lightingStyle: LightingHUDStyle {
        LightingHUDStyle(rawValue: lightingStyleRaw) ?? .glow
    }

    private var lightingSpeed: SoundHUDSpeed {
        SoundHUDSpeed(rawValue: lightingSpeedRaw) ?? .smooth
    }

    private var color: Color {
        switch presentation.control {
        case .volume:
            return SoundHUDAppearance.color(
                for: soundStyle,
                accent: albumAccent,
                level: presentation.level
            )
        case .displayBrightness, .keyboardBrightness:
            return SoundHUDAppearance.lightingColor(
                for: lightingStyle,
                control: presentation.control
            )
        }
    }

    private var showsPercentage: Bool {
        presentation.control == .volume
            ? showsSoundPercentage
            : showsLightingPercentage
    }

    private var hidesLabel: Bool {
        presentation.control == .volume
            ? hidesSoundLabel
            : hidesLightingLabel
    }

    private var presentationAnimation: Animation? {
        SoundHUDAppearance.animation(
            speed: presentation.control == .volume
                ? soundSpeed
                : lightingSpeed,
            reduceMotion: reduceMotion,
            applies: true
        )
    }

    private var glowColor: Color {
        if presentation.control == .volume {
            return SoundHUDAppearance.glow(
                for: soundStyle,
                accent: albumAccent,
                level: presentation.level,
                applies: true
            )
        }
        return SoundHUDAppearance.lightingGlow(
            for: lightingStyle,
            control: presentation.control
        )
    }

    private var glowRadius: CGFloat {
        guard presentation.control == .volume else {
            return SoundHUDAppearance.lightingGlowRadius(
                for: lightingStyle
            )
        }

        switch soundStyle {
        case .white:
            return 0
        case .accent:
            return 3
        case .decibel:
            return 7
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(presentationAnimation, value: presentation)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.control.title)
        .accessibilityValue("\(percentage)%")
    }

    private var island: some View {
        HStack(spacing: 12) {
            iconBadge(size: 38)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    if !hidesLabel {
                        Text(presentation.control.title)
                            .font(
                                .system(
                                    size: 12,
                                    weight: .semibold,
                                    design: .rounded
                                )
                            )
                            .foregroundStyle(.white.opacity(0.78))
                    }

                    if presentation.isFineAdjustment {
                        fineBadge
                    }

                    Spacer()

                    if showsPercentage {
                        Text("\(percentage)%")
                            .font(
                                .system(
                                    size: 13,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .frame(width: 38, alignment: .trailing)
                    }
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
        HStack(spacing: 10) {
            SoundHUDIcon(
                control: presentation.control,
                content: soundContent,
                level: presentation.level,
                isMuted: presentation.isMuted,
                color: color,
                size: 56,
                symbolScale: presentation.control == .volume ? 0.38 : 0.50
            )
            .offset(y: presentation.control == .volume ? 0 : 2)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if !hidesLabel {
                        Text(presentation.control.title)
                            .font(
                                .system(
                                    size: 12,
                                    weight: .semibold,
                                    design: .rounded
                                )
                            )
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    if presentation.isFineAdjustment {
                        fineBadge
                    }

                    Spacer(minLength: 0)

                    if showsPercentage {
                        Text("\(percentage)%")
                            .font(
                                .system(
                                    size: 15,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )
                            .monospacedDigit()
                            .foregroundStyle(color)
                            .contentTransition(.numericText())
                    }
                }

                horizontalProgress(height: 7)
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, minHeight: 76, maxHeight: 76)
    }

    private func iconBadge(size: CGFloat) -> some View {
        SoundHUDIcon(
            control: presentation.control,
            content: soundContent,
            level: presentation.level,
            isMuted: presentation.isMuted,
            color: color,
            size: size
        )
    }

    private func horizontalProgress(height: CGFloat) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.14))

                if presentation.level > 0 {
                    Capsule()
                        .fill(horizontalFill)
                        .frame(
                            width: max(
                                height,
                                geometry.size.width * presentation.level
                            )
                        )
                        .shadow(color: glowColor, radius: glowRadius)
                        .shadow(
                            color: presentation.control == .volume
                                ? .clear
                                : SoundHUDAppearance.lightingCoreGlow(
                                    for: lightingStyle
                                ),
                            radius: 2
                        )
                }
            }
        }
        .frame(height: height)
    }

    private var horizontalFill: AnyShapeStyle {
        if presentation.control != .volume && lightingStyle == .glow {
            return SoundHUDAppearance.lightingBeamStyle(vertical: false)
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: [color.opacity(0.66), color],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    private var fineBadge: some View {
        Text("微调")
            .font(.system(size: 8.5, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }

}

enum SoundHUDAppearance {
    static func color(
        for style: SoundHUDStyle,
        accent: Color,
        level: Double
    ) -> Color {
        switch style {
        case .white:
            return .white
        case .accent:
            return accent
        case .decibel:
            return decibelColor(for: level)
        }
    }

    static func glow(
        for style: SoundHUDStyle,
        accent: Color,
        level: Double,
        applies: Bool
    ) -> Color {
        guard applies else { return .clear }

        switch style {
        case .white:
            return .clear
        case .accent:
            return accent.opacity(0.28)
        case .decibel:
            return decibelColor(for: level).opacity(0.52)
        }
    }

    static func decibelColor(for level: Double) -> Color {
        let level = min(max(level, 0), 1)
        let hue: Double

        if level < 0.45 {
            hue = 0.38
        } else if level < 0.75 {
            hue = 0.38 - ((level - 0.45) / 0.30) * 0.24
        } else {
            hue = 0.14 - ((level - 0.75) / 0.25) * 0.14
        }

        return Color(hue: hue, saturation: 0.95, brightness: 1.0)
    }

    static func lightingColor(
        for style: LightingHUDStyle,
        control: SystemHUDControl
    ) -> Color {
        guard style == .accent else { return .white }

        switch control {
        case .keyboardBrightness:
            return Color(red: 0.48, green: 0.76, blue: 1.0)
        default:
            return Color(red: 1.0, green: 0.88, blue: 0.56)
        }
    }

    static func lightingBeamStyle(vertical: Bool) -> AnyShapeStyle {
        AnyShapeStyle(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.10),
                    Color.white.opacity(0.60),
                    .white
                ],
                startPoint: vertical ? .bottom : .leading,
                endPoint: vertical ? .top : .trailing
            )
        )
    }

    static func lightingGlow(
        for style: LightingHUDStyle,
        control: SystemHUDControl
    ) -> Color {
        switch style {
        case .white:
            return .clear
        case .accent:
            return lightingColor(for: style, control: control).opacity(0.28)
        case .glow:
            return Color.white.opacity(0.90)
        }
    }

    static func lightingCoreGlow(for style: LightingHUDStyle) -> Color {
        style == .glow ? Color.white.opacity(0.85) : .clear
    }

    static func lightingGlowRadius(for style: LightingHUDStyle) -> CGFloat {
        switch style {
        case .white:
            return 0
        case .accent:
            return 4
        case .glow:
            return 12
        }
    }

    static func animation(
        speed: SoundHUDSpeed,
        reduceMotion: Bool,
        applies: Bool
    ) -> Animation? {
        guard applies else {
            return .spring(response: 0.26, dampingFraction: 0.82)
        }
        guard !reduceMotion else {
            return .easeOut(duration: 0.12)
        }

        switch speed {
        case .smooth:
            return .spring(response: 0.52, dampingFraction: 0.88)
        case .fast:
            return .spring(response: 0.26, dampingFraction: 0.84)
        case .instant:
            return nil
        }
    }

    static func iconName(
        content: SoundHUDContent,
        control: SystemHUDControl,
        level: Double,
        isMuted: Bool
    ) -> String {
        if control == .volume {
            if content == .symbol,
               let model = SoundOutputDevice.preferredAirPodsModel() {
                return model.systemImage
            }
            if content == .device,
               let device = SoundOutputDevice.current() {
                return device.symbolName
            }
        }
        return control.symbolName(level: level, isMuted: isMuted)
    }
}

private struct SoundHUDIcon: View {
    let control: SystemHUDControl
    let content: SoundHUDContent
    let level: Double
    let isMuted: Bool
    let color: Color
    let size: CGFloat
    var showsBadge = false
    var symbolScale: CGFloat = 0.38

    private var airPodsModel: AirPodsModelKind? {
        guard control == .volume, content == .device else { return nil }
        return SoundOutputDevice.preferredAirPodsModel()
    }

    private var symbolName: String {
        SoundHUDAppearance.iconName(
            content: content,
            control: control,
            level: level,
            isMuted: isMuted
        )
    }

    var body: some View {
        ZStack {
            if showsBadge {
                Circle()
                    .fill(color.opacity(0.14))

                Circle()
                    .strokeBorder(color.opacity(0.22), lineWidth: 0.7)
            }

            if let airPodsModel {
                AirPods3DView(model: airPodsModel)
                    .id(airPodsModel)
                    .frame(width: size, height: size)
                    .scaleEffect(showsBadge ? 0.88 : 1)
                    .allowsHitTesting(false)
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: size * symbolScale, weight: .semibold))
                    .foregroundStyle(control == .volume ? .white : color)
            }
        }
        .frame(width: size, height: size)
    }
}
