import SwiftUI

enum BatteryHUDLayout {
    static let contentWidth: CGFloat = 270
    static let contentHeight: CGFloat = 44
    static let horizontalPadding: CGFloat = 22
    static let bottomPadding: CGFloat = 10
    static let cornerRadius: CGFloat = 18

    static func width(notchWidth: CGFloat) -> CGFloat {
        max(contentWidth, notchWidth) + cornerRadius * 2
    }

    static var horizontalInset: CGFloat {
        horizontalPadding + cornerRadius
    }

    static func height(topInset: CGFloat) -> CGFloat {
        topInset + contentHeight + bottomPadding
    }
}

enum BatteryHUDAppearance {
    static func tint(for presentation: BatteryHUDPresentation) -> Color {
        if presentation.isInLowPowerMode {
            return .yellow
        }

        switch presentation.kind {
        case .lowBattery:
            return .red
        case .fullBattery:
            return .green
        case .charging:
            if presentation.level <= 20, !presentation.isPluggedIn {
                return .red
            }
            return .green
        }
    }

    static func tint(for status: BatteryReading) -> Color {
        if status.isInLowPowerMode {
            return .yellow
        }
        if status.level <= 20,
           !status.isPluggedIn,
           !status.isCharging {
            return .red
        }
        if status.isPluggedIn || status.isCharging || status.isFullyCharged {
            return .green
        }
        return .white
    }

    static func title(for presentation: BatteryHUDPresentation) -> String {
        switch presentation.kind {
        case .lowBattery:
            return "电量低"
        case .fullBattery:
            return "已充满"
        case .charging:
            if presentation.isFullyCharged {
                return "已充满"
            }
            return presentation.isCharging ? "正在充电" : "已接入电源"
        }
    }

    static func detail(for presentation: BatteryHUDPresentation) -> String {
        switch presentation.kind {
        case .lowBattery:
            return presentation.isInLowPowerMode
                ? "低电量模式已开启，建议连接电源。"
                : "建议连接电源或开启低电量模式。"
        case .fullBattery:
            return "电池已达到 \(presentation.level)%，可以拔掉电源。"
        case .charging:
            if let minutes = presentation.timeToFullCharge {
                return "预计 \(minutes) 分钟充满"
            }
            return presentation.isCharging
                ? "正在为 Mac 补充电量"
                : "Mac 正在使用外部电源"
        }
    }

    static func statusSymbol(
        isCharging: Bool,
        isPluggedIn: Bool
    ) -> String? {
        if isCharging {
            return "bolt.fill"
        }
        if isPluggedIn {
            return "powerplug.fill"
        }
        return nil
    }
}

struct BatteryLevelGlyph: View {
    let level: Int
    let tint: Color
    var width: CGFloat = 46
    var height: CGFloat = 22
    var isCharging = false
    var isPluggedIn = false
    var showsPercentage = false
    var animationDuration: TimeInterval = 0.18

    private var fraction: CGFloat {
        min(max(CGFloat(level) / 100, 0), 1)
    }

    private var symbol: String? {
        BatteryHUDAppearance.statusSymbol(
            isCharging: isCharging,
            isPluggedIn: isPluggedIn
        )
    }

    var body: some View {
        HStack(spacing: max(1.5, height * 0.08)) {
            ZStack(alignment: .leading) {
                RoundedRectangle(
                    cornerRadius: height * 0.28,
                    style: .continuous
                )
                .fill(Color.white.opacity(0.12))

                GeometryReader { geometry in
                    if fraction > 0 {
                        RoundedRectangle(
                            cornerRadius: height * 0.22,
                            style: .continuous
                        )
                        .fill(
                            LinearGradient(
                                colors: [
                                    tint.opacity(0.72),
                                    tint
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: max(
                                2,
                                (geometry.size.width - 4) * fraction
                            ),
                            height: geometry.size.height - 4
                        )
                        .offset(x: 2, y: 2)
                    }
                }

                if showsPercentage {
                    HStack(spacing: 1.5) {
                        Text("\(level)")
                            .font(
                                .system(
                                    size: height * 0.52,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )
                            .monospacedDigit()

                        if let symbol {
                            Image(systemName: symbol)
                                .font(
                                    .system(
                                        size: height * 0.38,
                                        weight: .bold
                                    )
                                )
                        }
                    }
                    .foregroundStyle(.black.opacity(0.78))
                    .frame(maxWidth: .infinity)
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(
                            .system(
                                size: height * 0.55,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: width, height: height)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: height * 0.28,
                    style: .continuous
                )
            )

            RoundedRectangle(
                cornerRadius: max(1, height * 0.06),
                style: .continuous
            )
            .fill(tint.opacity(level >= 100 ? 1 : 0.58))
            .frame(
                width: max(2, height * 0.1),
                height: height * 0.38
            )
        }
        .animation(.smooth(duration: animationDuration), value: level)
        .animation(.smooth(duration: animationDuration), value: isCharging)
        .animation(.smooth(duration: animationDuration), value: isPluggedIn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("电池电量")
        .accessibilityValue("\(level)%")
    }
}

struct BatteryHUDView: View {
    let presentation: BatteryHUDPresentation
    let topInset: CGFloat

    @State private var pulse = false
    @State private var showsFullBatteryIndicator = false
    @State private var magSafeIndicatorIsOrange = true

    init(
        presentation: BatteryHUDPresentation,
        topInset: CGFloat
    ) {
        self.presentation = presentation
        self.topInset = topInset
        _showsFullBatteryIndicator = State(
            initialValue: presentation.kind == .fullBattery
        )
    }

    private var tint: Color {
        BatteryHUDAppearance.tint(for: presentation)
    }

    var body: some View {
        content
        .task(id: presentation.id) {
            await prepareAnimations()
        }
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(
                            .system(
                                size: 13,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)

                    Text("\(presentation.level)%")
                        .font(
                            .system(
                                size: 12,
                                weight: .semibold
                            )
                        )
                        .monospacedDigit()
                        .foregroundStyle(tint)
                }

                Text(description)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            indicator
                .frame(width: 70, height: 40, alignment: .trailing)
        }
        .padding(.horizontal, BatteryHUDLayout.horizontalInset)
        .padding(.top, topInset)
        .padding(.bottom, BatteryHUDLayout.bottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch presentation.kind {
        case .lowBattery:
            return "电池电量低"
        case .fullBattery:
            return "电池已充满"
        case .charging:
            return BatteryHUDAppearance.title(for: presentation)
        }
    }

    private var description: String {
        switch presentation.kind {
        case .lowBattery:
            return presentation.isInLowPowerMode
                ? "低电量模式已开启，建议连接电源。"
                : "开启低电量模式，或连接电源。"
        case .fullBattery:
            return "Mac 已充满电。"
        case .charging:
            return BatteryHUDAppearance.detail(for: presentation)
        }
    }

    @ViewBuilder
    private var indicator: some View {
        switch presentation.kind {
        case .lowBattery:
            if presentation.isInLowPowerMode {
                yellowLowIndicator
            } else {
                redLowIndicator
            }
        case .fullBattery:
            if showsFullBatteryIndicator {
                if presentation.isInLowPowerMode {
                    yellowFullIndicator
                        .transition(.opacity.combined(with: .scale))
                } else {
                    greenFullIndicator
                        .transition(.opacity.combined(with: .scale))
                }
            } else {
                magSafeIndicator
                    .transition(.opacity.combined(with: .scale))
            }
        case .charging:
            BatteryLevelGlyph(
                level: presentation.level,
                tint: tint,
                width: 56,
                height: 24,
                isCharging: presentation.isCharging,
                isPluggedIn: presentation.isPluggedIn
            )
        }
    }

    private var redLowIndicator: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(.red.opacity(0.2))
                .frame(width: 70, height: 40)

            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.red.opacity(0.4))
                    .frame(width: 40, height: 24)

                RoundedRectangle(cornerRadius: 10)
                    .fill(.red.opacity(0.4))
                    .frame(width: 3, height: 8)
            }
            .padding(.trailing, 5)

            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.gradient)
                .frame(width: 8, height: 14)
                .opacity(pulse ? 1 : 0.3)
                .offset(x: -15)

            RoundedRectangle(cornerRadius: 30)
                .stroke(Color.red.opacity(0.9), lineWidth: 1.5)
                .frame(
                    width: pulse ? 8 : 30,
                    height: pulse ? 14 : 32
                )
                .offset(x: -15)
                .opacity(pulse ? 0.3 : 1)
        }
        .frame(width: 70, height: 40)
    }

    private var yellowLowIndicator: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(.yellow.opacity(0.2))
                .frame(width: 70, height: 40)

            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.yellow.opacity(0.4))
                    .frame(width: 40, height: 24)

                RoundedRectangle(cornerRadius: 10)
                    .fill(.yellow.opacity(0.4))
                    .frame(width: 3, height: 8)
            }
            .padding(.trailing, 5)

            RoundedRectangle(cornerRadius: 8)
                .fill(Color.yellow.gradient)
                .frame(width: 8, height: 14)
                .offset(x: -15)
        }
        .frame(width: 70, height: 40)
    }

    private var greenFullIndicator: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(.green.opacity(0.2))
                .frame(width: 70, height: 40)

            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.green.opacity(0.4))
                    .frame(width: 44, height: 24)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.green.gradient)
                            .frame(width: 34, height: 14)
                            .opacity(pulse ? 1 : 0.4)
                    }

                RoundedRectangle(cornerRadius: 10)
                    .fill(.green.opacity(0.4))
                    .frame(width: 3, height: 8)
            }
        }
        .frame(width: 70, height: 40)
    }

    private var yellowFullIndicator: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(.yellow.opacity(0.2))
                .frame(width: 70, height: 40)

            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.yellow.opacity(0.4))
                    .frame(width: 44, height: 24)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.yellow.gradient)
                            .frame(width: 34, height: 14)
                            .opacity(pulse ? 1 : 0.4)
                    }

                RoundedRectangle(cornerRadius: 10)
                    .fill(.yellow.opacity(0.4))
                    .frame(width: 3, height: 8)
            }
        }
        .frame(width: 70, height: 40)
    }

    private var magSafeIndicator: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(.gray.opacity(0.15))
                .frame(width: 30, height: 5)

            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.gray.opacity(0.2).gradient)
                    .frame(width: 30, height: 40)

                Circle()
                    .fill(
                        magSafeIndicatorIsOrange ? .orange : .green
                    )
                    .shadow(
                        color: magSafeIndicatorIsOrange
                            ? .orange
                            : .green,
                        radius: 5
                    )
                    .frame(width: 5, height: 5)
            }

            Rectangle()
                .fill(.white.opacity(0.4))
                .frame(width: 3, height: 32)
        }
        .frame(width: 63, height: 40)
    }

    @MainActor
    private func prepareAnimations() async {
        pulse = false
        showsFullBatteryIndicator = presentation.kind == .fullBattery
        magSafeIndicatorIsOrange = true

        switch presentation.kind {
        case .charging:
            return
        case .lowBattery:
            guard !presentation.isInLowPowerMode else { return }
            withAnimation(
                .easeInOut(duration: 1)
                    .repeatForever(autoreverses: true)
            ) {
                pulse = true
            }
        case .fullBattery:
            withAnimation(
                .easeInOut(duration: 1)
                    .repeatForever(autoreverses: true)
            ) {
                pulse = true
            }

            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(duration: 0.4)) {
                showsFullBatteryIndicator = false
            }

            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(duration: 0.2)) {
                magSafeIndicatorIsOrange = false
            }
        }
    }
}

struct NotchSideBatteryHUDView: View {
    let presentation: BatteryHUDPresentation
    let notchWidth: CGFloat

    private var tint: Color {
        BatteryHUDAppearance.tint(for: presentation)
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                BatteryLevelGlyph(
                    level: presentation.level,
                    tint: tint,
                    width: 40,
                    height: 19,
                    isCharging: presentation.isCharging,
                    isPluggedIn: presentation.isPluggedIn
                )

                Text(BatteryHUDAppearance.title(for: presentation))
                    .font(
                        .system(
                            size: 10.5,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
            }

            Spacer(minLength: notchWidth)

            HStack(spacing: 5) {
                Text("\(presentation.level)%")
                    .font(
                        .system(
                            size: 10.5,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                    .foregroundStyle(tint)

                if let symbol = BatteryHUDAppearance.statusSymbol(
                    isCharging: presentation.isCharging,
                    isPluggedIn: presentation.isPluggedIn
                ) {
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(tint)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct NotchBatteryStatusView: View {
    let status: BatteryReading

    private var tint: Color {
        BatteryHUDAppearance.tint(for: status)
    }

    var body: some View {
        BatteryLevelGlyph(
            level: status.level,
            tint: tint,
            width: 34,
            height: 16,
            isCharging: status.isCharging,
            isPluggedIn: status.isPluggedIn,
            showsPercentage: true,
            animationDuration: 0.3
        )
        .frame(height: 24)
        .help(batteryHelp)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("电池")
        .accessibilityValue("\(status.level)%")
    }

    private var batteryHelp: String {
        if status.isCharging {
            return "电池 \(status.level)%，正在充电"
        }
        if status.isPluggedIn {
            return "电池 \(status.level)%，已接入电源"
        }
        return "电池 \(status.level)%，正在使用电池"
    }
}
