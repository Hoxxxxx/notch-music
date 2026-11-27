import SwiftUI

struct CompactSystemActivity: Identifiable {
    let id: String
    let icon: String
    let name: String?
    let tint: Color
    let accessibilityLabel: String
}

struct AirPodsStatusIcon: View {
    let model: AirPodsModelKind
    let size: CGFloat
    let content: SoundHUDContent

    var body: some View {
        Group {
            if content == .symbol {
                Image(systemName: model.systemImage)
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                AirPods3DView(model: model)
                    .id(model)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(model.displayName) 已连接")
    }
}

struct CompactBatteryRing: View {
    let level: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 2.4)

            Circle()
                .trim(from: 0, to: min(max(level, 0), 1))
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(red: 0.24, green: 1.0, blue: 0.53),
                            Color(red: 0.38, green: 1.0, blue: 0.66)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(
                        lineWidth: 2.4,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .shadow(
                    color: Color(red: 0.24, green: 1.0, blue: 0.53)
                        .opacity(0.48),
                    radius: 2.5
                )
                .animation(
                    .easeOut(duration: 0.22),
                    value: level
                )
        }
        .frame(width: 20, height: 20)
    }
}

struct CompactPlaybackIndicator: View {
    let color: Color
    let spectrumMonitor: AudioSpectrumMonitor

    var body: some View {
        TimelineView(.animation(minimumInterval: NotchTiming.thirtyFPS)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let levels = spectrumMonitor.levels

            HStack(alignment: .center, spacing: 1.8) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    color.opacity(0.52),
                                    color
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(
                            width: 2.2,
                            height: barHeight(
                                at: time,
                                index: index,
                                levels: levels
                            )
                        )
                }
            }
            .frame(width: 15, height: 14)
            .shadow(color: color.opacity(0.3), radius: 1.5)
        }
        .accessibilityLabel("正在播放")
    }

    private func barHeight(
        at time: TimeInterval,
        index: Int,
        levels: [CGFloat]
    ) -> CGFloat {
        let profile: [CGFloat] = [0.72, 1.0, 0.58, 0.84]

        if levels.contains(where: { $0 > 0.015 }) {
            let sourceIndex = min(
                levels.count - 1,
                Int(Double(index) / 4 * Double(levels.count))
            )
            return max(3, 14 * levels[sourceIndex] * profile[index])
        }
        let phase = time * 3.2 + Double(index) * 1.45
        return CGFloat(5 + (sin(phase) + 1) * 3.5) * profile[index]
    }
}

private enum CompactUnlockScene {
    static let animation = Animation.spring(
        response: 0.5,
        dampingFraction: 0.8
    )
    static let minimumScale: CGFloat = 0.72
}

struct CompactScreenStateIcon: View {
    let activity: CompactSystemActivity

    @State private var openProgress: CGFloat = 1
    @State private var lockAnimationTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isUnlocked: Bool {
        activity.icon == "lock.open.fill"
    }

    var body: some View {
        CompactLockGlyphShape(open: openProgress)
            .fill(activity.tint)
            .frame(width: 18, height: 18)
            .accessibilityLabel(activity.accessibilityLabel)
            .onAppear {
                if reduceMotion {
                    openProgress = isUnlocked ? 1 : 0
                } else if !isUnlocked {
                    lockAnimationTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        guard !Task.isCancelled else { return }
                        withAnimation(CompactUnlockScene.animation) {
                            openProgress = 0
                        }
                    }
                }
            }
            .onDisappear {
                lockAnimationTask?.cancel()
                lockAnimationTask = nil
            }
            .onChange(of: isUnlocked) { _, unlocked in
                lockAnimationTask?.cancel()
                lockAnimationTask = nil
                guard !reduceMotion else {
                    openProgress = unlocked ? 1 : 0
                    return
                }
                withAnimation(CompactUnlockScene.animation) {
                    openProgress = unlocked ? 1 : 0
                }
            }
    }
}

private struct CompactLockGlyphShape: Shape {
    var open: CGFloat

    var animatableData: CGFloat {
        get { open }
        set { open = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = CompactLockGlyph.bodyPath(in: rect)
        path.addPath(CompactLockGlyph.shacklePath(open: open, in: rect))
        return path
    }
}

private enum CompactLockGlyph {
    static func bodyPath(in rect: CGRect) -> Path {
        var path = Path()
        var index = 0
        for command in bodyCommands {
            switch command {
            case 0:
                path.move(to: map(bodyPoints[index], in: rect))
                index += 1
            case 1:
                path.addLine(to: map(bodyPoints[index], in: rect))
                index += 1
            case 2:
                path.addCurve(
                    to: map(bodyPoints[index + 2], in: rect),
                    control1: map(bodyPoints[index], in: rect),
                    control2: map(bodyPoints[index + 1], in: rect)
                )
                index += 3
            default:
                path.closeSubpath()
            }
        }
        return path
    }

    static func shacklePath(open: CGFloat, in rect: CGRect) -> Path {
        var path = Path()
        for segment in shackleSegments {
            let points = zip(segment.closed, segment.open).map { closed, openPoint in
                CGPoint(
                    x: closed.x + (openPoint.x - closed.x) * open,
                    y: closed.y + (openPoint.y - closed.y) * open
                )
            }
            switch segment.command {
            case 0:
                path.move(to: map(points[0], in: rect))
            case 1:
                path.addLine(to: map(points[0], in: rect))
            case 2:
                path.addCurve(
                    to: map(points[2], in: rect),
                    control1: map(points[0], in: rect),
                    control2: map(points[1], in: rect)
                )
            default:
                path.closeSubpath()
            }
        }
        return path
    }

    private static func map(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        let scale = rect.height / 18 * (15.6 / 25.57)
        return CGPoint(
            x: rect.midX + (point.x - 9.046) * scale,
            y: rect.midY + (point.y - 12.78) * scale
        )
    }

    static let bodyCommands: [UInt8] = [
        0, 1, 2, 1, 2, 1, 2, 1, 2, 3
    ]

    static let bodyPoints: [CGPoint] = [
        CGPoint(x: 2.996, y: 25.565),
        CGPoint(x: 15.097, y: 25.565),
        CGPoint(x: 17.071, y: 25.565),
        CGPoint(x: 18.093, y: 24.524),
        CGPoint(x: 18.093, y: 22.383),
        CGPoint(x: 18.093, y: 13.212),
        CGPoint(x: 18.093, y: 11.090),
        CGPoint(x: 17.071, y: 10.049),
        CGPoint(x: 15.097, y: 10.049),
        CGPoint(x: 2.996, y: 10.049),
        CGPoint(x: 1.021, y: 10.049),
        CGPoint(x: 0.000, y: 11.090),
        CGPoint(x: 0.000, y: 13.212),
        CGPoint(x: 0.000, y: 22.383),
        CGPoint(x: 0.000, y: 24.524),
        CGPoint(x: 1.021, y: 25.565),
        CGPoint(x: 2.996, y: 25.565)
    ]

    static let shackleSegments: [LockShackleSegment] = [
        LockShackleSegment(
            command: 0,
            closed: [CGPoint(x: 2.405, y: 11.180)],
            open: [CGPoint(x: 13.140, y: 11.180)]
        ),
        LockShackleSegment(
            command: 1,
            closed: [CGPoint(x: 5.050, y: 11.180)],
            open: [CGPoint(x: 15.785, y: 11.180)]
        ),
        LockShackleSegment(
            command: 1,
            closed: [CGPoint(x: 5.050, y: 6.914)],
            open: [CGPoint(x: 15.785, y: 6.914)]
        ),
        LockShackleSegment(
            command: 2,
            closed: [
                CGPoint(x: 5.050, y: 4.110),
                CGPoint(x: 6.859, y: 2.542),
                CGPoint(x: 9.043, y: 2.542)
            ],
            open: [
                CGPoint(x: 15.785, y: 4.110),
                CGPoint(x: 17.594, y: 2.542),
                CGPoint(x: 19.785, y: 2.542)
            ]
        ),
        LockShackleSegment(
            command: 2,
            closed: [
                CGPoint(x: 11.227, y: 2.542),
                CGPoint(x: 13.055, y: 4.110),
                CGPoint(x: 13.055, y: 6.914)
            ],
            open: [
                CGPoint(x: 21.962, y: 2.542),
                CGPoint(x: 23.790, y: 4.110),
                CGPoint(x: 23.790, y: 6.914)
            ]
        ),
        LockShackleSegment(
            command: 1,
            closed: [CGPoint(x: 13.055, y: 11.180)],
            open: [CGPoint(x: 23.790, y: 9.704)]
        ),
        LockShackleSegment(
            command: 2,
            closed: [
                CGPoint(x: 13.055, y: 11.180),
                CGPoint(x: 14.000, y: 11.180),
                CGPoint(x: 14.378, y: 11.180)
            ],
            open: [
                CGPoint(x: 23.790, y: 10.580),
                CGPoint(x: 24.381, y: 11.120),
                CGPoint(x: 25.118, y: 11.120)
            ]
        ),
        LockShackleSegment(
            command: 2,
            closed: [
                CGPoint(x: 14.378, y: 11.180),
                CGPoint(x: 15.118, y: 11.180),
                CGPoint(x: 15.700, y: 11.180)
            ],
            open: [
                CGPoint(x: 25.843, y: 11.120),
                CGPoint(x: 26.435, y: 10.608),
                CGPoint(x: 26.435, y: 9.704)
            ]
        ),
        LockShackleSegment(
            command: 1,
            closed: [CGPoint(x: 15.700, y: 7.102)],
            open: [CGPoint(x: 26.435, y: 7.102)]
        ),
        LockShackleSegment(
            command: 2,
            closed: [
                CGPoint(x: 15.700, y: 2.487),
                CGPoint(x: 12.620, y: 0.000),
                CGPoint(x: 9.043, y: 0.000)
            ],
            open: [
                CGPoint(x: 26.435, y: 2.487),
                CGPoint(x: 23.353, y: 0.000),
                CGPoint(x: 19.785, y: 0.000)
            ]
        ),
        LockShackleSegment(
            command: 2,
            closed: [
                CGPoint(x: 5.473, y: 0.000),
                CGPoint(x: 2.405, y: 2.487),
                CGPoint(x: 2.405, y: 7.102)
            ],
            open: [
                CGPoint(x: 16.205, y: 0.000),
                CGPoint(x: 13.140, y: 2.487),
                CGPoint(x: 13.140, y: 7.102)
            ]
        ),
        LockShackleSegment(command: 3, closed: [], open: [])
    ]
}

private struct LockShackleSegment {
    let command: UInt8
    let closed: [CGPoint]
    let open: [CGPoint]
}

struct CompactUnlockResultIcon: View {
    let systemName: String
    let tint: Color
    let label: String
    let wobbles: Bool

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shouldWobble = wobbles && !reduceMotion

        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 18, height: 18)
            .scaleEffect(
                appeared || reduceMotion
                    ? 1
                    : CompactUnlockScene.minimumScale,
                anchor: .center
            )
            .opacity(appeared || reduceMotion ? 1 : 0)
            .keyframeAnimator(
                initialValue: 0.0,
                trigger: appeared
            ) { content, angle in
                content.rotationEffect(.degrees(angle))
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(shouldWobble ? -13 : 0, duration: 0.10)
                    CubicKeyframe(shouldWobble ? 11 : 0, duration: 0.11)
                    CubicKeyframe(shouldWobble ? -5 : 0, duration: 0.08)
                    CubicKeyframe(shouldWobble ? 2 : 0, duration: 0.06)
                    CubicKeyframe(0, duration: 0.06)
                }
            }
            .accessibilityLabel(label)
            .onAppear {
                guard !appeared else { return }
                if reduceMotion {
                    appeared = true
                } else {
                    withAnimation(CompactUnlockScene.animation) {
                        appeared = true
                    }
                }
            }
    }
}

private struct CompactUnlockCheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(
            to: CGPoint(
                x: rect.minX + rect.width * 0.2,
                y: rect.minY + rect.height * 0.53
            )
        )
        path.addLine(
            to: CGPoint(
                x: rect.minX + rect.width * 0.4,
                y: rect.minY + rect.height * 0.72
            )
        )
        path.addLine(
            to: CGPoint(
                x: rect.minX + rect.width * 0.8,
                y: rect.minY + rect.height * 0.29
            )
        )
        return path
    }
}

struct CompactUnlockCheckIcon: View {
    let tint: Color
    let label: String

    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CompactUnlockCheckShape()
            .trim(from: 0, to: reduceMotion ? 1 : progress)
            .stroke(
                tint,
                style: StrokeStyle(
                    lineWidth: 2,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .frame(width: 18, height: 18)
            .accessibilityLabel(label)
            .onAppear {
                guard progress == 0 else { return }
                if reduceMotion {
                    progress = 1
                } else {
                    withAnimation(.easeOut(duration: 0.42)) {
                        progress = 1
                    }
                }
            }
    }
}

