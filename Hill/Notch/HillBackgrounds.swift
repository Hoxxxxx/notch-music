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
    let spectrumMonitor: AudioSpectrumMonitor
    let isExpanded: Bool
    let topInset: CGFloat
    let isScreenLocked: Bool

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
                        spectrumMonitor: spectrumMonitor,
                        isPaused: isScreenLocked
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
