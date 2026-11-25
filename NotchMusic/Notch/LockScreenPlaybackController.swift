import AppKit
import Combine
import SwiftUI

enum LockScreenPlaybackSettings {
    static let isEnabledKey = "NotchMusic.lockScreenPlaybackEnabled"
    static let backgroundStyleKey =
        "NotchMusic.lockScreenPlaybackBackgroundStyle"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: isEnabledKey) as? Bool ?? true
    }
}

enum LockScreenBackgroundStyle: String, CaseIterable, Identifiable {
    case liquidGlass
    case tintedGlass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .liquidGlass:
            return "液态玻璃"
        case .tintedGlass:
            return "深色玻璃"
        }
    }
}

@MainActor
final class LockScreenPlaybackModel: ObservableObject {
    @Published var showsLyrics: Bool

    init() {
        showsLyrics = false
#if DEBUG
        if ProcessInfo.processInfo.environment[
            "NOTCHMUSIC_LOCKSCREEN_LYRICS"
        ] == "1" {
            showsLyrics = true
        }
#endif
    }
}

final class LockScreenPlaybackPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class LockScreenPlaybackHostingView<Content: View>:
    NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

@MainActor
final class LockScreenPlaybackController {
    private let musicMonitor: MusicMonitor
    private let systemActivityMonitor: SystemActivityMonitor
    private let appVolumeMixer: AppVolumeMixer
    private let model = LockScreenPlaybackModel()
    private let panel: LockScreenPlaybackPanel
    private let lockScreenIsland = LockScreenIslandController()
    private var cancellables: Set<AnyCancellable> = []
    private var isPresented = false

    init(
        musicMonitor: MusicMonitor,
        systemActivityMonitor: SystemActivityMonitor,
        appVolumeMixer: AppVolumeMixer
    ) {
        self.musicMonitor = musicMonitor
        self.systemActivityMonitor = systemActivityMonitor
        self.appVolumeMixer = appVolumeMixer

        let panel = LockScreenPlaybackPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.panel = panel

        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true

        panel.contentView = LockScreenPlaybackHostingView(
            rootView: LockScreenPlaybackView(
                musicMonitor: musicMonitor,
                appVolumeMixer: appVolumeMixer,
                model: model
            )
        )
        panel.contentView?.wantsLayer = true
        panel.contentView?.autoresizingMask = [.width, .height]
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    }

    func start() {
#if DEBUG
        if ProcessInfo.processInfo.environment[
            "NOTCHMUSIC_LOCKSCREEN_PREVIEW"
        ] == "1" {
            updateWindowFrame()
            panel.orderFrontRegardless()
            isPresented = true
            return
        }
#endif
        systemActivityMonitor.$isScreenLocked
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshVisibility()
                }
            }
            .store(in: &cancellables)

        musicMonitor.$snapshot
            .map { $0 != nil }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshVisibility()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(
            for: UserDefaults.didChangeNotification
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            Task { @MainActor in
                self?.refreshVisibility()
            }
        }
        .store(in: &cancellables)

        refreshVisibility()
    }

    func screenParametersDidChange() {
        guard isPresented else { return }
        updateWindowFrame()
    }

    func stop() {
        guard isPresented else { return }
        isPresented = false
        lockScreenIsland.leave(panel: panel, orderFront: false)
        panel.orderOut(nil)
    }

    private func refreshVisibility() {
        let shouldShow = LockScreenPlaybackSettings.isEnabled
            && systemActivityMonitor.isScreenLocked
            && musicMonitor.snapshot != nil
        guard shouldShow else {
            guard isPresented else { return }
            isPresented = false
            model.showsLyrics = false
            lockScreenIsland.leave(panel: panel, orderFront: false)
            panel.orderOut(nil)
            return
        }

        updateWindowFrame()
        if isPresented {
            panel.orderFrontRegardless()
            return
        }

        isPresented = lockScreenIsland.enter(
            panel: panel,
            interactive: true
        )
        if !isPresented {
            panel.orderOut(nil)
        }
    }

    private func updateWindowFrame(animated: Bool = false) {
        guard let screen = lockScreenScreen() else { return }

        let cardWidth = min(screen.frame.width * 0.21, 350)
        let cardHeight = cardWidth * 0.44
        let margin: CGFloat = 18
        let size = CGSize(
            width: cardWidth + margin * 2,
            height: cardHeight + margin * 2
        )
        // Keep the card just above the lock-screen credential stack.
        let centerY = screen.frame.midY - screen.frame.height * 0.11
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: centerY - size.height / 2,
            width: size.width,
            height: size.height
        )

        if animated, isPresented {
            panel.setFrame(frame, display: true, animate: true)
            return
        }

        panel.setFrame(frame, display: true)
        panel.contentView?.frame = NSRect(origin: .zero, size: frame.size)
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    private func lockScreenScreen() -> NSScreen? {
        NSScreen.screens.first
    }
}

struct LockScreenPlaybackView: View {
    @ObservedObject var musicMonitor: MusicMonitor
    @ObservedObject var appVolumeMixer: AppVolumeMixer
    @ObservedObject var model: LockScreenPlaybackModel
    var snapshotOverride: MusicSnapshot? = nil
    var allowsInteraction = true
    @StateObject private var lyricsController = LyricsController()
    @AppStorage(LockScreenPlaybackSettings.backgroundStyleKey)
    private var backgroundStyleRaw =
        LockScreenBackgroundStyle.tintedGlass.rawValue

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let shadowMargin: CGFloat = 18
    private let referenceCardWidth: CGFloat = 350

    var body: some View {
        GeometryReader { proxy in
            let cardWidth = max(
                0,
                proxy.size.width - shadowMargin * 2
            )
            let cardHeight = cardWidth * 0.44

            if let snapshot = snapshotOverride ?? musicMonitor.snapshot,
               cardWidth > 0 {
                let scale = cardWidth / referenceCardWidth
                let shape = RoundedRectangle(
                    cornerRadius: 20 * scale,
                    style: .continuous
                )

                card(
                    snapshot: snapshot,
                    scale: scale,
                    shape: shape
                )
                    .frame(width: cardWidth, height: cardHeight)
                    .clipShape(shape)
                    .overlay {
                        shape.strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(
                                        backgroundStyle == .liquidGlass
                                            ? 0.14
                                            : 0.20
                                    ),
                                    Color.white.opacity(
                                        backgroundStyle == .liquidGlass
                                            ? 0.02
                                            : 0.03
                                    )
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: backgroundStyle == .liquidGlass
                                ? 0.5
                                : 0.6
                        )
                    }
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
            }
        }
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(allowsInteraction)
        .onChange(of: model.showsLyrics) { _, showsLyrics in
            guard showsLyrics, let snapshot = musicMonitor.snapshot else {
                return
            }
            lyricsController.load(for: snapshot)
        }
        .onChange(of: musicMonitor.snapshot?.trackID) { _, _ in
            guard model.showsLyrics, let snapshot = musicMonitor.snapshot else {
                return
            }
            lyricsController.load(for: snapshot)
        }
        .task(id: model.showsLyrics) {
            guard model.showsLyrics,
                  let snapshot = musicMonitor.snapshot else {
                return
            }
            lyricsController.load(for: snapshot)
        }
    }

    private func card(
        snapshot: MusicSnapshot,
        scale: CGFloat,
        shape: RoundedRectangle
    ) -> some View {
        ZStack {
            cardBackground(
                shape: shape,
                cornerRadius: 20 * scale
            )

            ZStack {
                if model.showsLyrics {
                    lyricsLayout(snapshot: snapshot, scale: scale)
                        .transition(
                            .opacity.combined(
                                with: .scale(scale: 0.985)
                            )
                        )
                } else {
                    playerLayout(snapshot: snapshot, scale: scale)
                        .transition(
                            .opacity.combined(
                                with: .scale(scale: 0.985)
                            )
                        )
                }
            }
            .padding(.horizontal, 16 * scale)
            .padding(.top, 16 * scale)
            .padding(.bottom, 8 * scale)
        }
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .spring(response: 0.34, dampingFraction: 0.86),
            value: model.showsLyrics
        )
    }

    @ViewBuilder
    private func cardBackground(
        shape: RoundedRectangle,
        cornerRadius: CGFloat
    ) -> some View {
        switch backgroundStyle {
        case .liquidGlass:
            LockScreenLiquidGlassBackdrop(
                cornerRadius: cornerRadius
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        case .tintedGlass:
            shape
                .fill(.ultraThinMaterial)
                .overlay {
                    shape.fill(Color.black.opacity(0.36))
                }
                .overlay {
                    shape.fill(Color.white.opacity(0.02))
                }
        }
    }

    private var backgroundStyle: LockScreenBackgroundStyle {
        LockScreenBackgroundStyle(rawValue: backgroundStyleRaw)
            ?? .tintedGlass
    }

    private func playerLayout(
        snapshot: MusicSnapshot,
        scale: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            nowPlayingHeader(snapshot: snapshot, scale: scale)
                .frame(height: 50 * scale)

            Spacer(minLength: 4 * scale)

            progress(snapshot: snapshot, scale: scale)

            Spacer(minLength: 4 * scale)

            controls(snapshot: snapshot, scale: scale)
        }
    }

    private func nowPlayingHeader(
        snapshot: MusicSnapshot,
        scale: CGFloat
    ) -> some View {
        HStack(alignment: .center, spacing: 11 * scale) {
            artwork(snapshot: snapshot, scale: scale)

            VStack(alignment: .leading, spacing: 3 * scale) {
                OverflowMarqueeText(
                    text: snapshot.title,
                    font: .system(
                        size: 16.5 * scale,
                        weight: .semibold
                    ),
                    color: .white,
                    speed: 10 * scale,
                    gap: 14 * scale
                )
                .frame(height: 20 * scale)

                Text(snapshot.artist)
                    .font(
                        .system(
                            size: 12.5 * scale,
                            weight: .regular
                        )
                    )
                    .foregroundStyle(Color.white.opacity(0.62))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func artwork(
        snapshot: MusicSnapshot,
        scale: CGFloat
    ) -> some View {
        let size = 50 * scale
        let shape = RoundedRectangle(
            cornerRadius: 6 * scale,
            style: .continuous
        )

        Group {
            if let image = snapshot.artwork {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(nsColor: snapshot.accentColor),
                            Color.black.opacity(0.72)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Image(systemName: "music.note")
                        .font(
                            .system(
                                size: 14 * scale,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(Color.white.opacity(0.74))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.28), radius: 3 * scale, y: 1.5 * scale)
    }

    private func lyricsLayout(
        snapshot: MusicSnapshot,
        scale: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                MusicLyricsView(
                    snapshot: snapshot,
                    state: lyricsController.state,
                    width: proxy.size.width,
                    height: proxy.size.height,
                    showsBackButton: false,
                    compact: true,
                    onBack: {
                        model.showsLyrics = false
                    },
                    onRetry: {
                        lyricsController.retry(for: snapshot)
                    }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            progress(snapshot: snapshot, scale: scale)
                .padding(.top, 3 * scale)

            controls(snapshot: snapshot, scale: scale)
                .padding(.top, 3 * scale)
        }
    }

    private func progress(
        snapshot: MusicSnapshot,
        scale: CGFloat
    ) -> some View {
        LockScreenProgressBar(
            musicMonitor: musicMonitor,
            snapshot: snapshot,
            scale: scale
        )
    }

    private func controls(
        snapshot: MusicSnapshot,
        scale: CGFloat
    ) -> some View {
        ZStack {
            HStack(spacing: 18 * scale) {
                LockScreenControlButton(
                    systemName: "backward.fill",
                    label: "上一首",
                    size: 13 * scale,
                    frameSize: 26 * scale,
                    action: musicMonitor.previousTrack
                )

                LockScreenControlButton(
                    systemName: snapshot.isPlaying ? "pause.fill" : "play.fill",
                    label: snapshot.isPlaying ? "暂停" : "播放",
                    size: 18 * scale,
                    frameSize: 32 * scale,
                    action: musicMonitor.togglePlayPause
                )

                LockScreenControlButton(
                    systemName: "forward.fill",
                    label: "下一首",
                    size: 13 * scale,
                    frameSize: 26 * scale,
                    action: musicMonitor.nextTrack
                )
            }

            HStack {
                LockScreenControlButton(
                    systemName: model.showsLyrics
                        ? "quote.bubble.fill"
                        : "quote.bubble",
                    label: model.showsLyrics ? "返回播放界面" : "歌词",
                    size: 14 * scale,
                    frameSize: 30 * scale,
                    isActive: model.showsLyrics
                ) {
                    model.showsLyrics.toggle()
                }

                Spacer(minLength: 0)

                outputDeviceMenu(scale: scale)
            }
        }
        .frame(height: 32 * scale)
    }

    private func outputDeviceMenu(scale: CGFloat) -> some View {
        Menu {
            ForEach(
                appVolumeMixer.outputDevices.filter(\.canBeDefaultOutput)
            ) { device in
                Button {
                    appVolumeMixer.setSystemOutputDevice(device.uid)
                } label: {
                    if device.isDefault {
                        Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
        } label: {
            Image(systemName: outputDeviceSymbol)
                .font(.system(size: 14 * scale, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.68))
                .frame(width: 30 * scale, height: 30 * scale)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(appVolumeMixer.outputDevices.isEmpty)
        .help("输出设备：\(currentOutputName)")
        .accessibilityLabel("输出设备")
    }

    private var outputDeviceSymbol: String {
        let name = currentOutputName.lowercased()
        if name.contains("airpods") {
            return "airpodspro"
        }
        if name.contains("headphone")
            || name.contains("耳机")
            || name.contains("headset") {
            return "headphones"
        }
        if name.contains("display")
            || name.contains("显示器")
            || name.contains("studio display") {
            return "display"
        }
        return "airplayaudio"
    }

    private var currentOutputName: String {
        appVolumeMixer.outputDevices.first(where: \.isDefault)?.name
            ?? "系统输出"
    }
}

private struct LockScreenControlButton: View {
    let systemName: String
    let label: String
    let size: CGFloat
    let frameSize: CGFloat
    var isActive = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(
                    isActive
                        ? Color.white
                        : Color.white.opacity(isHovering ? 0.94 : 0.76)
                )
                .frame(width: frameSize, height: frameSize)
                .contentShape(Rectangle())
                .scaleEffect(isHovering ? 1.04 : 1)
                .animation(
                    .easeOut(duration: 0.14),
                    value: isHovering
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct LockScreenProgressBar: View {
    @ObservedObject var musicMonitor: MusicMonitor
    let snapshot: MusicSnapshot
    let scale: CGFloat

    @State private var scrubbedPosition: TimeInterval?
    @State private var isEditing = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let position = scrubbedPosition
                ?? snapshot.elapsed(at: context.date)

            HStack(spacing: 7 * scale) {
                Text(formatTime(position))
                    .frame(width: 26 * scale, alignment: .leading)

                GeometryReader { proxy in
                    slider(
                        width: proxy.size.width,
                        position: position
                    )
                }
                .frame(height: 18 * scale)

                Text("-\(formatTime(max(0, snapshot.duration - position)))")
                    .frame(width: 34 * scale, alignment: .trailing)
            }
            .font(
                .system(
                    size: 10.5 * scale,
                    weight: .medium,
                    design: .rounded
                )
            )
            .monospacedDigit()
            .foregroundStyle(Color.white.opacity(0.60))
            .frame(height: 18 * scale)
        }
    }

    private func slider(
        width: CGFloat,
        position: TimeInterval
    ) -> some View {
        let thumbSize = 8.5 * scale
        let trackInset = thumbSize / 2
        let usableWidth = max(width - thumbSize, 1)
        let fraction = snapshot.duration > 0
            ? min(max(position / snapshot.duration, 0), 1)
            : 0
        let thumbCenter = trackInset + usableWidth * fraction
        let filledWidth = min(max(thumbCenter, 0), width)

        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.white.opacity(0.20))
                .frame(width: width, height: 3 * scale)

            Capsule()
                .fill(Color.white.opacity(0.92))
                .frame(
                    width: filledWidth,
                    height: 3 * scale
                )

            Circle()
                .fill(Color.white.opacity(0.96))
                .frame(width: thumbSize, height: thumbSize)
                .scaleEffect(isEditing ? 1.15 : 1)
                .position(x: thumbCenter, y: 9 * scale)
        }
        .frame(width: width, height: 18 * scale)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    guard snapshot.duration > 0 else { return }
                    isEditing = true
                    let fraction = dragFraction(
                        at: gesture.location.x,
                        width: width,
                        thumbSize: thumbSize
                    )
                    scrubbedPosition = snapshot.duration
                        * Double(fraction)
                }
                .onEnded { gesture in
                    guard snapshot.duration > 0 else { return }
                    let fraction = dragFraction(
                        at: gesture.location.x,
                        width: width,
                        thumbSize: thumbSize
                    )
                    musicMonitor.seek(
                        to: snapshot.duration * Double(fraction)
                    )
                    scrubbedPosition = nil
                    isEditing = false
                }
        )
        .animation(
            .easeOut(duration: 0.14),
            value: isEditing
        )
        .accessibilityElement()
        .accessibilityLabel("播放进度")
        .accessibilityValue(
            "\(Int((fraction * 100).rounded()))%"
        )
    }

    private func dragFraction(
        at x: CGFloat,
        width: CGFloat,
        thumbSize: CGFloat
    ) -> Double {
        let usableWidth = max(width - thumbSize, 1)
        return Double(
            min(
                max((x - thumbSize / 2) / usableWidth, 0),
                1
            )
        )
    }

    private func formatTime(_ value: TimeInterval) -> String {
        guard value.isFinite, value > 0 else { return "0:00" }

        let total = Int(value.rounded(.down))
        return String(
            format: "%d:%02d",
            total / 60,
            total % 60
        )
    }
}

