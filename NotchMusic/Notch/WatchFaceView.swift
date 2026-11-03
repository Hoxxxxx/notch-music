import AppKit
import Foundation
import SwiftUI

enum WatchFaceStyle: String, CaseIterable, Identifiable {
    case classic
    case singleLine
    case flow
    case flux
    case dualLine
    case happyTime
    case avatar
    case emoji
    case rainbowFlow
    case rainbowMosaic
    case rainbowGlow
    case rainbowConfetti
    case customImage

    static let storageKey = "NotchMusic.watchFaceStyle"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic:
            return "经典"
        case .singleLine:
            return "单行数字"
        case .flow:
            return "流动"
        case .flux:
            return "流转"
        case .dualLine:
            return "双行数字"
        case .happyTime:
            return "欢乐时光"
        case .avatar:
            return "头像"
        case .emoji:
            return "表情"
        case .rainbowFlow:
            return "彩虹流光"
        case .rainbowMosaic:
            return "彩虹和谐"
        case .rainbowGlow:
            return "彩虹光辉"
        case .rainbowConfetti:
            return "彩虹庆典"
        case .customImage:
            return "自定义图片"
        }
    }
}

enum WatchFaceEmojiSettings {
    static let storageKey = "NotchMusic.watchFaceEmoji"
    static let defaultEmoji = "😀"

    static func normalized(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return defaultEmoji }
        return String(first)
    }
}

enum WatchFaceClockSettings {
    static let uses24HourKey = "NotchMusic.watchFaceUses24Hour"
}

enum WatchFaceSurfaceMetrics {
    static let cornerRadiusRatio: CGFloat = 24.0 / 88.0
}

enum WatchFaceImageSettings {
    static let pathKey = "NotchMusic.watchFaceCustomImagePath"
    static let cropKey = "NotchMusic.watchFaceCustomImageCrop"
    static let defaultCrop = CGRect(
        x: 0.11,
        y: 0.11,
        width: 0.78,
        height: 0.78
    )

    private static let cache = NSCache<NSString, NSImage>()

    static func normalizedCrop(_ rawValue: String) -> CGRect {
        let values = rawValue
            .split(separator: ",")
            .compactMap { Double($0) }
        guard values.count == 4,
              values.allSatisfy({ $0.isFinite }) else {
            return defaultCrop
        }

        let x = min(max(CGFloat(values[0]), 0), 1)
        let y = min(max(CGFloat(values[1]), 0), 1)
        let width = min(max(CGFloat(values[2]), 0.01), 1 - x)
        let height = min(max(CGFloat(values[3]), 0.01), 1 - y)

        guard width > 0, height > 0 else { return defaultCrop }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func encodedCrop(_ crop: CGRect) -> String {
        String(
            format: "%.6f,%.6f,%.6f,%.6f",
            locale: Locale(identifier: "en_US_POSIX"),
            crop.minX,
            crop.minY,
            crop.width,
            crop.height
        )
    }

    static func centeredCrop(for image: NSImage) -> CGRect {
        let size = image.size
        guard size.width > 0, size.height > 0 else {
            return defaultCrop
        }

        let side = min(size.width, size.height) * 0.78
        let width = side / size.width
        let height = side / size.height
        return CGRect(
            x: (1 - width) / 2,
            y: (1 - height) / 2,
            width: width,
            height: height
        )
    }

    static func croppedImage(
        path: String,
        crop: CGRect
    ) -> NSImage? {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        let cacheKey = "\(path)|\(encodedCrop(crop))" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        guard let source = NSImage(contentsOfFile: path),
              let sourceCG = source.cgImage(
                  forProposedRect: nil,
                  context: nil,
                  hints: nil
              ) else {
            return nil
        }

        let imageBounds = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(sourceCG.width),
            height: CGFloat(sourceCG.height)
        )
        let pixelRect = CGRect(
            x: crop.minX * imageBounds.width,
            y: crop.minY * imageBounds.height,
            width: crop.width * imageBounds.width,
            height: crop.height * imageBounds.height
        )
            .integral
            .intersection(imageBounds)
        guard pixelRect.width >= 1,
              pixelRect.height >= 1,
              let croppedCG = sourceCG.cropping(to: pixelRect) else {
            return nil
        }

        let image = NSImage(
            cgImage: croppedCG,
            size: NSSize(
                width: CGFloat(croppedCG.width),
                height: CGFloat(croppedCG.height)
            )
        )
        cache.setObject(image, forKey: cacheKey)
        return image
    }

    static func saveImage(_ image: NSImage) throws -> String {
        let directory = try imageDirectory()
        let url = directory.appendingPathComponent(
            "watch-face-\(UUID().uuidString).png"
        )

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(
                  using: .png,
                  properties: [:]
              ) else {
            throw WatchFaceImageError.encodingFailed
        }

        try pngData.write(to: url, options: .atomic)
        cache.removeAllObjects()
        return url.path
    }

    static func removeImage(at path: String) {
        guard !path.isEmpty else { return }
        try? FileManager.default.removeItem(atPath: path)
        cache.removeAllObjects()
    }

    private static func imageDirectory() throws -> URL {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw WatchFaceImageError.storageUnavailable
        }

        let directory = applicationSupport
            .appendingPathComponent("NotchMusic", isDirectory: true)
            .appendingPathComponent("WatchFaces", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}

private enum WatchFaceImageError: LocalizedError {
    case encodingFailed
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "无法处理所选图片。"
        case .storageUnavailable:
            return "无法创建表盘图片存储目录。"
        }
    }
}

struct WatchFaceView: View {
    let style: WatchFaceStyle
    let accent: Color
    var size: CGFloat = 88

    @AppStorage(WatchFaceClockSettings.uses24HourKey)
    private var uses24Hour = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let time = WatchFaceTime(
                date: context.date,
                uses24Hour: uses24Hour
            )

            face(at: time)
                .frame(width: 88, height: 88)
                .scaleEffect(size / 88)
                .frame(width: size, height: size)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("时间")
                .accessibilityValue(time.shortTimeText)
        }
    }

    @ViewBuilder
    private func face(at time: WatchFaceTime) -> some View {
        switch style {
        case .classic:
            ClassicWatchFace(time: time, accent: accent)
        case .singleLine:
            SingleLineWatchFace(time: time, accent: accent)
        case .flow:
            FlowWatchFace(time: time)
        case .flux:
            FluxWatchFace(time: time)
        case .dualLine:
            DualLineWatchFace(time: time)
        case .happyTime:
            HappyTimeWatchFace(time: time)
        case .avatar:
            AvatarWatchFace(time: time, accent: accent)
        case .emoji:
            EmojiWatchFace(time: time, accent: accent)
        case .rainbowFlow:
            RainbowFlowWatchFace(time: time)
        case .rainbowMosaic:
            RainbowMosaicWatchFace(time: time)
        case .rainbowGlow:
            RainbowGlowWatchFace(time: time)
        case .rainbowConfetti:
            RainbowConfettiWatchFace(time: time)
        case .customImage:
            CustomImageWatchFace(time: time, accent: accent)
        }
    }
}

private struct WatchFaceTime {
    let date: Date
    let hour: Int
    let minute: Int
    let second: Int
    let uses24Hour: Bool

    init(date: Date, uses24Hour: Bool) {
        self.date = date
        self.uses24Hour = uses24Hour
        let components = Calendar.autoupdatingCurrent.dateComponents(
            [.hour, .minute, .second],
            from: date
        )
        hour = components.hour ?? 0
        minute = components.minute ?? 0
        second = components.second ?? 0
    }

    var hour12: Int {
        let value = hour % 12
        return value == 0 ? 12 : value
    }

    var hourText: String {
        String(format: "%02d", uses24Hour ? hour : hour12)
    }

    var minuteText: String {
        String(format: "%02d", minute)
    }

    var shortTimeText: String {
        "\(hourText):\(minuteText)"
    }

    var hourAngle: Double {
        let hours = Double(hour % 12) + (Double(minute) + Double(second) / 60) / 60
        return hours / 12 * 2 * .pi - .pi / 2
    }

    var minuteAngle: Double {
        (Double(minute) + Double(second) / 60) / 60 * 2 * .pi - .pi / 2
    }

    var secondAngle: Double {
        Double(second) / 60 * 2 * .pi - .pi / 2
    }
}

private struct ClassicWatchFace: View {
    let time: WatchFaceTime
    let accent: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            Color(white: 0.05),
                            Color(white: 0.16),
                            Color(white: 0.07),
                            Color(white: 0.13),
                            Color(white: 0.05)
                        ],
                        center: .center
                    )
                )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            accent.opacity(0.22),
                            .clear
                        ],
                        center: UnitPoint(x: 0.28, y: 0.24),
                        startRadius: 0,
                        endRadius: 54
                    )
                )

            ClassicWatchDial(time: time, accent: accent)

            VStack(spacing: 0) {
                Text(time.date, format: .dateTime.weekday(.abbreviated))
                    .font(.system(size: 6.5, weight: .bold, design: .rounded))
                    .tracking(0.35)
                    .foregroundStyle(.white.opacity(0.52))

                Spacer(minLength: 0)

                Text(time.shortTimeText)
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
            }
            .padding(.top, 13)
            .padding(.bottom, 10)
            .frame(width: 64, height: 72)
        }
        .clipShape(Circle())
        .modifier(WatchFaceGlassBackground(shape: Circle()))
        .overlay {
            Circle()
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        }
        .overlay {
            Circle()
                .inset(by: 3)
                .stroke(Color.white.opacity(0.035), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.34), radius: 4, y: 2)
    }
}

private struct ClassicWatchDial: View {
    let time: WatchFaceTime
    let accent: Color

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2

            for index in 0..<60 {
                let isMajor = index.isMultiple(of: 5)
                let angle = Double(index) / 60 * 2 * .pi - .pi / 2
                let outerRadius = radius - 6
                let innerRadius = outerRadius - (isMajor ? 4.2 : 1.8)
                var tick = Path()
                tick.move(to: point(from: center, angle: angle, radius: innerRadius))
                tick.addLine(to: point(from: center, angle: angle, radius: outerRadius))
                context.stroke(
                    tick,
                    with: .color(.white.opacity(isMajor ? 0.76 : 0.18)),
                    style: StrokeStyle(
                        lineWidth: isMajor ? 1.25 : 0.5,
                        lineCap: .round
                    )
                )
            }

            context.stroke(
                handPath(
                    from: center,
                    angle: time.hourAngle,
                    length: radius * 0.44
                ),
                with: .color(.white.opacity(0.94)),
                style: StrokeStyle(lineWidth: 3.4, lineCap: .round)
            )
            context.stroke(
                handPath(
                    from: center,
                    angle: time.minuteAngle,
                    length: radius * 0.66
                ),
                with: .color(.white),
                style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
            )

            let secondTip = point(
                from: center,
                angle: time.secondAngle,
                radius: radius * 0.69
            )
            var secondHand = Path()
            secondHand.move(to: center)
            secondHand.addLine(to: secondTip)
            context.stroke(
                secondHand,
                with: .color(accent),
                style: StrokeStyle(lineWidth: 1.15, lineCap: .round)
            )

            let capRect = CGRect(
                x: center.x - 2.6,
                y: center.y - 2.6,
                width: 5.2,
                height: 5.2
            )
            context.fill(Path(ellipseIn: capRect), with: .color(.black))
            context.stroke(
                Path(ellipseIn: capRect.insetBy(dx: 0.75, dy: 0.75)),
                with: .color(accent),
                lineWidth: 1.2
            )
        }
    }

    private func point(
        from center: CGPoint,
        angle: Double,
        radius: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }

    private func handPath(
        from center: CGPoint,
        angle: Double,
        length: CGFloat
    ) -> Path {
        var path = Path()
        path.move(to: center)
        path.addLine(to: point(from: center, angle: angle, radius: length))
        return path
    }
}

private struct SingleLineWatchFace: View {
    let time: WatchFaceTime
    let accent: Color

    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.022, blue: 0.018)

            Text(time.hourText)
                .font(.system(size: 80, weight: .black, design: .rounded))
                .tracking(-9)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.95, blue: 0.84),
                            Color(red: 0.91, green: 0.79, blue: 0.59)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .frame(width: 82, height: 88)

            AnalogHandsOverlay(
                time: time,
                handColor: .white.opacity(0.9),
                secondColor: accent,
                centerColor: accent
            )
        }
        .watchFaceSurface()
    }
}

private struct FlowWatchFace: View {
    let time: WatchFaceTime

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRotating = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.81, green: 0.63, blue: 0.97),
                    Color(red: 0.55, green: 0.33, blue: 0.86)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            FlowBlobField()
                .rotationEffect(.degrees(isRotating ? 360 : 0))
                .animation(
                    reduceMotion
                        ? nil
                        : .linear(duration: 24).repeatForever(autoreverses: false),
                    value: isRotating
                )

            VStack(spacing: 4) {
                glassTime(time.hourText)
                glassTime(time.minuteText)
            }
        }
        .watchFaceSurface()
        .onAppear {
            isRotating = true
        }
    }

    private func glassTime(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 31, weight: .black, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.94))
            .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
            .frame(width: 58, height: 30)
    }
}

private struct FlowBlobField: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(Color(red: 0.92, green: 0.42, blue: 0.94).opacity(0.72))
                .frame(width: 19, height: 36)
                .rotationEffect(.degrees(18))
                .offset(x: -22, y: -16)
                .blur(radius: 2.5)

            Circle()
                .fill(Color(red: 0.80, green: 0.31, blue: 0.98).opacity(0.74))
                .frame(width: 37, height: 37)
                .offset(x: 22, y: -17)
                .blur(radius: 3)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.73, green: 0.55, blue: 0.98).opacity(0.74))
                .frame(width: 27, height: 31)
                .rotationEffect(.degrees(-22))
                .offset(x: -22, y: 23)
                .blur(radius: 3)

            Capsule()
                .fill(Color(red: 0.66, green: 0.39, blue: 0.95).opacity(0.78))
                .frame(width: 19, height: 40)
                .rotationEffect(.degrees(18))
                .offset(x: 23, y: 23)
                .blur(radius: 2.5)
        }
        .frame(width: 88, height: 88)
    }
}

private struct FluxWatchFace: View {
    let time: WatchFaceTime

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        Color(red: 0.35, green: 0.52, blue: 0.96),
                        Color(red: 0.43, green: 0.61, blue: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                LinearGradient(
                    colors: [
                        Color(red: 0.36, green: 0.91, blue: 0.52),
                        Color(red: 0.49, green: 1.0, blue: 0.63)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }

            VStack(spacing: -4) {
                Text(time.hourText)
                    .foregroundStyle(.white.opacity(0.84))
                    .frame(height: 44)

                Text(time.minuteText)
                    .foregroundStyle(.black.opacity(0.76))
                    .frame(height: 44)
            }
            .font(.system(size: 43, weight: .black, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(width: 78)
        }
        .watchFaceSurface()
    }
}

private struct DualLineWatchFace: View {
    let time: WatchFaceTime

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.032, blue: 0.035),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: -8) {
                Text(time.hourText)
                    .foregroundStyle(Color(red: 1.0, green: 0.67, blue: 0.57))
                    .frame(height: 42)

                Text(time.minuteText)
                    .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.32))
                    .frame(height: 42)
            }
            .font(.system(size: 46, weight: .black, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(width: 78)

            AnalogHandsOverlay(
                time: time,
                handColor: .white.opacity(0.5),
                secondColor: .white.opacity(0.32),
                centerColor: .white.opacity(0.64)
            )
        }
        .watchFaceSurface()
    }
}

private struct HappyTimeWatchFace: View {
    let time: WatchFaceTime

    var body: some View {
        ZStack {
            Color.black

            HappyTimeStarField()

            VStack(spacing: 1) {
                HStack(spacing: 17) {
                    ToyCharacter(
                        bodyColor: Color(red: 0.86, green: 0.88, blue: 0.82),
                        accent: Color(red: 0.88, green: 0.35, blue: 0.66),
                        hat: true
                    )
                    ToyCharacter(
                        bodyColor: Color(red: 0.94, green: 0.91, blue: 0.82),
                        accent: Color(red: 1.0, green: 0.64, blue: 0.16),
                        hat: false
                    )
                }

                HStack(spacing: 21) {
                    ToyCharacter(
                        bodyColor: Color(red: 0.84, green: 0.91, blue: 0.86),
                        accent: Color(red: 0.24, green: 0.74, blue: 0.82),
                        hat: false
                    )
                    ToyCharacter(
                        bodyColor: Color(red: 0.86, green: 0.84, blue: 0.76),
                        accent: Color(red: 0.48, green: 0.72, blue: 0.36),
                        hat: true
                    )
                }
            }
            .offset(y: -3)

            VStack {
                Spacer()

                Text(time.shortTimeText)
                    .font(.system(size: 7.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .padding(.bottom, 7)
            }
        }
        .watchFaceSurface()
    }
}

private struct ToyCharacter: View {
    let bodyColor: Color
    let accent: Color
    let hat: Bool

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.white.opacity(0.62))
                .frame(width: 2, height: 10)
                .rotationEffect(.degrees(-42))
                .offset(x: -7, y: 15)

            Capsule()
                .fill(Color.white.opacity(0.62))
                .frame(width: 2, height: 10)
                .rotationEffect(.degrees(38))
                .offset(x: 7, y: 15)

            Capsule()
                .fill(bodyColor)
                .frame(width: 11, height: 17)
                .offset(y: 6)

            Circle()
                .fill(bodyColor)
                .frame(width: 16, height: 16)
                .offset(y: -7)

            HStack(spacing: 4) {
                Circle()
                    .fill(Color.black.opacity(0.78))
                    .frame(width: 2, height: 2)

                Circle()
                    .fill(Color.black.opacity(0.78))
                    .frame(width: 2, height: 2)
            }
            .offset(y: -7)

            Capsule()
                .fill(accent)
                .frame(width: 7, height: 2)
                .rotationEffect(.degrees(hat ? -14 : 10))
                .offset(y: 1)

            if hat {
                Triangle()
                    .fill(accent)
                    .frame(width: 9, height: 8)
                    .rotationEffect(.degrees(-8))
                    .offset(x: -2, y: -18)
            }
        }
        .frame(width: 24, height: 34)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct HappyTimeStarField: View {
    private let stars: [(CGFloat, CGFloat, CGFloat, Color)] = [
        (0.10, 0.20, 3.6, Color(red: 0.92, green: 0.38, blue: 0.64)),
        (0.78, 0.14, 3.0, Color(red: 1.0, green: 0.70, blue: 0.18)),
        (0.18, 0.67, 2.8, Color(red: 0.30, green: 0.78, blue: 0.65)),
        (0.83, 0.63, 3.8, Color(red: 0.48, green: 0.58, blue: 0.95)),
        (0.62, 0.84, 2.5, Color(red: 0.92, green: 0.40, blue: 0.58)),
        (0.34, 0.12, 2.4, Color(red: 0.66, green: 0.52, blue: 0.92))
    ]

    var body: some View {
        Canvas { context, size in
            for star in stars {
                let center = CGPoint(
                    x: size.width * star.0,
                    y: size.height * star.1
                )
                let radius = star.2
                var path = Path()
                path.move(to: CGPoint(x: center.x, y: center.y - radius))
                path.addLine(to: CGPoint(x: center.x + radius * 0.32, y: center.y))
                path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
                path.addLine(to: CGPoint(x: center.x - radius * 0.32, y: center.y))
                path.closeSubpath()
                context.fill(path, with: .color(star.3))
            }
        }
    }
}

private struct AvatarWatchFace: View {
    let time: WatchFaceTime
    let accent: Color

    @AppStorage(MultiAvatarSettings.seedKey)
    private var avatarSeed = MultiAvatarSettings.defaultSeed

    var body: some View {
        ZStack {
            Color(red: 0.045, green: 0.045, blue: 0.055)

            if let image = MultiAvatarRenderer.image(for: avatarSeed) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 84, height: 84)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.82), Color.black],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                    .overlay {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(.white.opacity(0.78))
                    }
            }

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.44),
                    .init(color: .black.opacity(0.62), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                Text(time.date, format: .dateTime.weekday(.abbreviated).day())
                    .font(.system(size: 6.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.84))
                    .shadow(color: .black.opacity(0.7), radius: 1.5, y: 0.5)
                    .padding(.top, 8)

                Spacer()

                Text(time.shortTimeText)
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.82), radius: 2, y: 1)
                    .padding(.bottom, 7)
            }
        }
        .watchFaceSurface()
    }
}

private struct EmojiWatchFace: View {
    let time: WatchFaceTime
    let accent: Color

    @AppStorage(WatchFaceEmojiSettings.storageKey)
    private var emoji = WatchFaceEmojiSettings.defaultEmoji

    private var displayEmoji: String {
        WatchFaceEmojiSettings.normalized(emoji)
    }

    var body: some View {
        ZStack {
            AngularGradient(
                colors: [
                    Color(red: 0.055, green: 0.055, blue: 0.07),
                    Color(red: 0.12, green: 0.09, blue: 0.14),
                    Color(red: 0.045, green: 0.045, blue: 0.055),
                    Color(red: 0.10, green: 0.075, blue: 0.11),
                    Color(red: 0.055, green: 0.055, blue: 0.07)
                ],
                center: .center
            )

            RadialGradient(
                colors: [
                    accent.opacity(0.34),
                    accent.opacity(0.08),
                    .clear
                ],
                center: UnitPoint(x: 0.5, y: 0.43),
                startRadius: 2,
                endRadius: 48
            )

            Text(displayEmoji)
                .font(.system(size: 46))
                .lineLimit(1)
                .offset(y: -3)
                .shadow(color: .black.opacity(0.28), radius: 3, y: 2)

            VStack(spacing: 0) {
                Text(time.date, format: .dateTime.weekday(.abbreviated))
                    .font(.system(size: 6.5, weight: .bold, design: .rounded))
                    .tracking(0.45)
                    .foregroundStyle(.white.opacity(0.52))
                    .padding(.top, 8)

                Spacer(minLength: 0)

                Text(time.shortTimeText)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.72), radius: 2, y: 1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .padding(.bottom, 7)
            }
        }
        .watchFaceSurface()
    }
}

private struct CustomImageWatchFace: View {
    let time: WatchFaceTime
    let accent: Color

    @AppStorage(WatchFaceImageSettings.pathKey)
    private var imagePath = ""
    @AppStorage(WatchFaceImageSettings.cropKey)
    private var cropRawValue = ""

    private var crop: CGRect {
        WatchFaceImageSettings.normalizedCrop(cropRawValue)
    }

    var body: some View {
        ZStack {
            Color(red: 0.045, green: 0.045, blue: 0.055)

            if let image = WatchFaceImageSettings.croppedImage(
                path: imagePath,
                crop: crop
            ) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: 88, height: 88)
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.78), Color.black],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(.white.opacity(0.82))
                    }
            }

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.42),
                    .init(color: .black.opacity(0.64), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                Text(time.date, format: .dateTime.weekday(.abbreviated).day())
                    .font(.system(size: 6.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.86))
                    .shadow(color: .black.opacity(0.72), radius: 1.5, y: 0.5)
                    .padding(.top, 8)

                Spacer()

                Text(time.shortTimeText)
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.84), radius: 2, y: 1)
                    .padding(.bottom, 7)
            }
        }
        .watchFaceSurface()
    }
}

private struct RainbowFlowWatchFace: View {
    let time: WatchFaceTime

    var body: some View {
        ZStack {
            AngularGradient(
                colors: [
                    Color(red: 0.96, green: 0.42, blue: 0.50),
                    Color(red: 1.0, green: 0.73, blue: 0.42),
                    Color(red: 0.88, green: 0.91, blue: 0.55),
                    Color(red: 0.52, green: 0.86, blue: 0.69),
                    Color(red: 0.42, green: 0.67, blue: 0.96),
                    Color(red: 0.65, green: 0.49, blue: 0.94),
                    Color(red: 0.96, green: 0.55, blue: 0.74),
                    Color(red: 0.94, green: 0.40, blue: 0.48)
                ],
                center: .center
            )

            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 52, height: 52)
                .blur(radius: 10)

            VStack {
                Text(time.date, format: .dateTime.weekday(.abbreviated).day())
                    .font(.system(size: 6.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.84))
                    .padding(.top, 11)

                Spacer()
            }

            AnalogHandsOverlay(
                time: time,
                handColor: .white,
                secondColor: .white.opacity(0.72),
                centerColor: .white
            )
        }
        .watchFaceSurface()
    }
}

private struct RainbowMosaicWatchFace: View {
    let time: WatchFaceTime

    private let colors: [Color] = [
        Color(red: 0.92, green: 0.35, blue: 0.31),
        Color(red: 0.96, green: 0.69, blue: 0.24),
        Color(red: 0.36, green: 0.68, blue: 0.42),
        Color(red: 0.31, green: 0.57, blue: 0.91),
        Color(red: 0.54, green: 0.36, blue: 0.71),
        Color(red: 0.91, green: 0.53, blue: 0.66),
        Color(red: 0.73, green: 0.84, blue: 0.90),
        Color(red: 0.96, green: 0.89, blue: 0.70)
    ]

    var body: some View {
        ZStack {
            Canvas { context, size in
                let cellWidth = size.width / 5
                let cellHeight = size.height / 5

                for row in 0..<5 {
                    for column in 0..<5 {
                        let index = (row * 3 + column * 5) % colors.count
                        let rect = CGRect(
                            x: CGFloat(column) * cellWidth,
                            y: CGFloat(row) * cellHeight,
                            width: cellWidth + 0.5,
                            height: cellHeight + 0.5
                        )
                        context.fill(
                            Path(rect),
                            with: .color(colors[index].opacity(0.94))
                        )
                    }
                }

                let darkColumn = CGRect(
                    x: cellWidth * 2,
                    y: cellHeight,
                    width: cellWidth,
                    height: cellHeight * 3
                )
                context.fill(
                    Path(darkColumn),
                    with: .color(Color.black.opacity(0.8))
                )
            }

            VStack {
                Text(time.date, format: .dateTime.weekday(.abbreviated).day())
                    .font(.system(size: 6.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.top, 11)

                Spacer()
            }

            AnalogHandsOverlay(
                time: time,
                handColor: .white.opacity(0.96),
                secondColor: Color(red: 0.91, green: 0.47, blue: 0.24),
                centerColor: .white
            )
        }
        .watchFaceSurface()
    }
}

private struct RainbowGlowWatchFace: View {
    let time: WatchFaceTime

    private let gradient = AngularGradient(
        colors: [
            Color(red: 1.0, green: 0.34, blue: 0.42),
            Color(red: 1.0, green: 0.67, blue: 0.25),
            Color(red: 0.87, green: 0.92, blue: 0.36),
            Color(red: 0.30, green: 0.83, blue: 0.63),
            Color(red: 0.30, green: 0.62, blue: 0.98),
            Color(red: 0.72, green: 0.39, blue: 0.96),
            Color(red: 0.98, green: 0.34, blue: 0.65)
        ],
        center: .center
    )

    var body: some View {
        ZStack {
            Color.black

            VStack(spacing: -7) {
                Text(time.hourText)
                Text(time.minuteText)
            }
            .font(.system(size: 35, weight: .black, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(gradient)
            .blur(radius: 3.4)
            .opacity(0.8)

            VStack(spacing: -7) {
                Text(time.hourText)
                Text(time.minuteText)
            }
            .font(.system(size: 35, weight: .black, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(gradient)
            .shadow(color: .white.opacity(0.18), radius: 0.6)

            VStack {
                Text(time.date, format: .dateTime.weekday(.abbreviated).day())
                    .font(.system(size: 6, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))
                    .padding(.top, 8)

                Spacer()
            }
        }
        .watchFaceSurface()
    }
}

private struct RainbowConfettiWatchFace: View {
    let time: WatchFaceTime

    var body: some View {
        ZStack {
            Color(red: 0.93, green: 0.91, blue: 0.87)

            RainbowConfettiField()

            VStack {
                Text(time.date, format: .dateTime.weekday(.abbreviated).day())
                    .font(.system(size: 6.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.56))
                    .padding(.top, 10)

                Spacer()

                Text(time.shortTimeText)
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.black.opacity(0.52))
                    .padding(.bottom, 8)
            }

            AnalogHandsOverlay(
                time: time,
                handColor: Color.black.opacity(0.72),
                secondColor: Color(red: 0.95, green: 0.48, blue: 0.25),
                centerColor: Color.black.opacity(0.72)
            )
        }
        .watchFaceSurface()
    }
}

private struct RainbowConfettiField: View {
    private let colors: [Color] = [
        Color(red: 0.92, green: 0.32, blue: 0.30),
        Color(red: 0.96, green: 0.60, blue: 0.22),
        Color(red: 0.36, green: 0.70, blue: 0.45),
        Color(red: 0.30, green: 0.54, blue: 0.91),
        Color(red: 0.65, green: 0.38, blue: 0.82)
    ]

    private let pieces: [(CGFloat, CGFloat, CGFloat, CGFloat, Int)] = [
        (0.12, 0.16, 11, 3.4, 0),
        (0.78, 0.12, 8, 2.8, 1),
        (0.22, 0.74, 9, 4.2, 2),
        (0.82, 0.63, 12, 3.6, 3),
        (0.52, 0.18, 7, 2.4, 4),
        (0.62, 0.83, 10, 3.0, 1),
        (0.10, 0.48, 8, 2.5, 3),
        (0.89, 0.37, 8, 3.1, 0)
    ]

    var body: some View {
        Canvas { context, size in
            for (index, piece) in pieces.enumerated() {
                let center = CGPoint(
                    x: size.width * piece.0,
                    y: size.height * piece.1
                )
                let length = piece.2
                let width = piece.3
                let color = colors[piece.4]

                context.drawLayer { layer in
                    layer.translateBy(x: center.x, y: center.y)
                    layer.rotate(by: .degrees(piece.0 * 360 + CGFloat(index * 17)))

                    if index.isMultiple(of: 3) {
                        let circle = CGRect(
                            x: -length / 2,
                            y: -length / 2,
                            width: length,
                            height: length
                        )
                        layer.fill(
                            Path(ellipseIn: circle),
                            with: .color(color.opacity(0.86))
                        )
                    } else {
                        let rect = CGRect(
                            x: -length / 2,
                            y: -width / 2,
                            width: length,
                            height: width
                        )
                        layer.fill(
                            Path(roundedRect: rect, cornerRadius: width / 2),
                            with: .color(color.opacity(0.9))
                        )
                    }
                }
            }
        }
    }
}

private struct AnalogHandsOverlay: View {
    let time: WatchFaceTime
    let handColor: Color
    let secondColor: Color
    let centerColor: Color

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2

            drawHand(
                in: &context,
                center: center,
                angle: time.hourAngle,
                start: -4,
                end: radius * 0.38,
                width: 3,
                color: handColor
            )
            drawHand(
                in: &context,
                center: center,
                angle: time.minuteAngle,
                start: -5,
                end: radius * 0.59,
                width: 2,
                color: handColor
            )
            drawHand(
                in: &context,
                center: center,
                angle: time.secondAngle,
                start: -7,
                end: radius * 0.69,
                width: 1,
                color: secondColor
            )

            let cap = CGRect(
                x: center.x - 2.8,
                y: center.y - 2.8,
                width: 5.6,
                height: 5.6
            )
            context.fill(Path(ellipseIn: cap), with: .color(.black.opacity(0.35)))
            context.fill(
                Path(ellipseIn: cap.insetBy(dx: 1.3, dy: 1.3)),
                with: .color(centerColor)
            )
        }
    }

    private func drawHand(
        in context: inout GraphicsContext,
        center: CGPoint,
        angle: Double,
        start: CGFloat,
        end: CGFloat,
        width: CGFloat,
        color: Color
    ) {
        var shadow = Path()
        shadow.move(to: point(from: center, angle: angle, radius: start, offset: 0.8))
        shadow.addLine(to: point(from: center, angle: angle, radius: end, offset: 0.8))
        context.stroke(
            shadow,
            with: .color(.black.opacity(0.24)),
            style: StrokeStyle(lineWidth: width, lineCap: .round)
        )

        var hand = Path()
        hand.move(to: point(from: center, angle: angle, radius: start))
        hand.addLine(to: point(from: center, angle: angle, radius: end))
        context.stroke(
            hand,
            with: .color(color),
            style: StrokeStyle(lineWidth: width, lineCap: .round)
        )
    }

    private func point(
        from center: CGPoint,
        angle: Double,
        radius: CGFloat,
        offset: CGFloat = 0
    ) -> CGPoint {
        CGPoint(
            x: center.x + cos(angle) * radius + offset,
            y: center.y + sin(angle) * radius + offset
        )
    }
}

private struct WatchFaceSurface: ViewModifier {
    private let shape = RoundedRectangle(
        cornerRadius: 88 * WatchFaceSurfaceMetrics.cornerRadiusRatio,
        style: .continuous
    )

    func body(content: Content) -> some View {
        content
            .modifier(WatchFaceGlassBackground(shape: shape))
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.34), radius: 4, y: 2)
    }
}

private struct WatchFaceGlassBackground<S: Shape>: ViewModifier {
    let shape: S

    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency

    func body(content: Content) -> some View {
        ZStack {
            WatchFaceGlassSurface(shape: shape)

            content
                .opacity(reduceTransparency ? 1 : 0.82)
        }
    }
}

private struct WatchFaceGlassSurface<S: Shape>: View {
    let shape: S

    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency

    @ViewBuilder
    var body: some View {
        if reduceTransparency {
            Color.clear
        } else if #available(macOS 26.0, *) {
            shape
                .fill(.clear)
                .glassEffect(.regular, in: shape)
        } else {
            shape
                .fill(.ultraThinMaterial)
                .opacity(0.42)
        }
    }
}

private extension View {
    func watchFaceSurface() -> some View {
        modifier(WatchFaceSurface())
    }
}
