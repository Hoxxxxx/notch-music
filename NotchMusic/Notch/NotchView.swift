import AppKit
import SwiftUI

enum MusicControlItem: String, CaseIterable, Identifiable {
    case shuffle
    case previous
    case playPause
    case next
    case volume

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shuffle:
            return "随机播放"
        case .previous:
            return "上一首"
        case .playPause:
            return "播放 / 暂停"
        case .next:
            return "下一首"
        case .volume:
            return "音量"
        }
    }

    var systemImage: String {
        switch self {
        case .shuffle:
            return "shuffle"
        case .previous:
            return "backward.fill"
        case .playPause:
            return "playpause.fill"
        case .next:
            return "forward.fill"
        case .volume:
            return "speaker.wave.2.fill"
        }
    }
}

enum MusicControlLayoutSettings {
    static let storageKey = "NotchMusic.musicControlLayout"
    static let defaultSlots: [MusicControlItem?] = [
        .shuffle,
        .previous,
        .playPause,
        .next,
        .volume
    ]
    private static let legacyDefaultRawValue =
        "previous,playPause,next,volume"
    private static let shuffleMigrationKey =
        "NotchMusic.musicControlLayout.shuffleMigration"

    static var slotCount: Int { defaultSlots.count }
    static var defaultRawValue: String { encode(defaultSlots) }

    static func migrateStoredValueIfNeeded(
        defaults: UserDefaults = .standard
    ) {
        guard !defaults.bool(forKey: shuffleMigrationKey) else { return }
        defaults.set(true, forKey: shuffleMigrationKey)

        guard defaults.string(forKey: storageKey) == legacyDefaultRawValue else {
            return
        }
        defaults.set(defaultRawValue, forKey: storageKey)
    }

    static func decode(_ rawValue: String) -> [MusicControlItem?] {
        let tokens = rawValue.split(
            separator: ",",
            omittingEmptySubsequences: false
        )
        .map(String.init)
        .filter { $0 != "spectrum" }
        var seen = Set<MusicControlItem>()
        var slots = [MusicControlItem?](
            repeating: nil,
            count: slotCount
        )

        for index in 0..<min(tokens.count, slotCount) {
            guard let item = MusicControlItem(rawValue: tokens[index]),
                  seen.insert(item).inserted else {
                continue
            }
            slots[index] = item
        }

        return slots
    }

    static func encode(_ slots: [MusicControlItem?]) -> String {
        slots.prefix(slotCount)
            .map { $0?.rawValue ?? "" }
            .joined(separator: ",")
    }
}

enum ProgressTrackStyle: String, CaseIterable, Identifiable {
    case classic
    case softAurora

    static let storageKey = "NotchMusic.progressTrackStyle"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic:
            return "默认"
        case .softAurora:
            return "Soft Aurora"
        }
    }

    var systemImage: String {
        switch self {
        case .classic:
            return "capsule.fill"
        case .softAurora:
            return "water.waves"
        }
    }
}

enum NotchBackgroundEffect: String, CaseIterable, Identifiable {
    case aurora
    case threads
    case hyperspeed
    case galaxy
    case gradientWaves
    case aeroShards
    case pixelMatrix
    case spectrum

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .aurora:
            return "Aurora"
        case .threads:
            return "Threads"
        case .hyperspeed:
            return "Hyperspeed"
        case .galaxy:
            return "Galaxy"
        case .gradientWaves:
            return "Gradient Waves"
        case .aeroShards:
            return "Aero Shards"
        case .pixelMatrix:
            return "Pixel Matrix"
        case .spectrum:
            return "Spectrum"
        }
    }

    var systemImage: String {
        switch self {
        case .aurora:
            return "water.waves"
        case .threads:
            return "music.note.list"
        case .hyperspeed:
            return "wind"
        case .galaxy:
            return "sparkles"
        case .gradientWaves:
            return "waveform.path"
        case .aeroShards:
            return "square.stack.3d.up.fill"
        case .pixelMatrix:
            return "circle.grid.3x3.fill"
        case .spectrum:
            return "waveform"
        }
    }
}

enum NotchBackgroundSettings {
    static let enabled = "NotchMusic.notchBackground.enabled"
    static let effect = "NotchMusic.notchBackground.effect"
}

private enum NotchContentPage: String, CaseIterable, Identifiable {
    case music
    case calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .music:
            return "音乐"
        case .calendar:
            return "日历"
        }
    }

    var systemImage: String {
        switch self {
        case .music:
            return "music.note"
        case .calendar:
            return "calendar"
        }
    }
}

private enum ContentPageTransitionDirection {
    case forward
    case backward
}

private enum PixelTypography {
    static let pixel = "Fusion-Pixel-12px-Prop-zh-Hans-Regular"

    static func font(size: CGFloat) -> Font {
        .custom(pixel, fixedSize: size)
    }
}

struct NotchView: View {
    @ObservedObject var musicMonitor: MusicMonitor
    @ObservedObject var panelState: NotchPanelState
    @ObservedObject var systemActivityMonitor: SystemActivityMonitor
    @ObservedObject var audioSpectrumMonitor: AudioSpectrumMonitor
    @ObservedObject var systemHUDController: SystemHUDController
    @ObservedObject var deviceConnectionMonitor: DeviceConnectionMonitor
    let onOpenSettings: () -> Void

    @State private var scrubPosition: TimeInterval?
    @State private var showsVolumeSlider = false
    @State private var selectedContentPage = NotchContentPage.music
    @State private var contentPageTransitionDirection =
        ContentPageTransitionDirection.forward
    @State private var outgoingContentPage: NotchContentPage?
    @State private var contentPageTransitionProgress: CGFloat = 1
    @State private var pageSwitchTask: Task<Void, Never>?
    @AppStorage(MusicControlLayoutSettings.storageKey)
    private var musicControlLayoutRaw =
        MusicControlLayoutSettings.defaultRawValue
    @AppStorage(ProgressTrackStyle.storageKey)
    private var progressTrackStyleRaw = ProgressTrackStyle.classic.rawValue
    @AppStorage(NotchBackgroundSettings.enabled)
    private var notchBackgroundEnabled = true
    @AppStorage(NotchBackgroundSettings.effect)
    private var notchBackgroundEffectRaw = NotchBackgroundEffect.aurora.rawValue
    @AppStorage(SystemHUDSettings.style)
    private var systemHUDStyleRaw = SystemHUDStyle.island.rawValue
    @AppStorage(WatchFaceStyle.storageKey)
    private var watchFaceStyleRaw = WatchFaceStyle.classic.rawValue
    @AppStorage(SystemDetectionSettings.screenRecordingIndicator)
    private var showsScreenRecordingIndicator = true
    @AppStorage(SystemDetectionSettings.focusIndicator)
    private var showsFocusIndicator = true
    @AppStorage(SystemDetectionSettings.focusLabel)
    private var showsFocusLabel = true
    @AppStorage(SystemDetectionSettings.focusCompactHint)
    private var usesCompactFocusHint = false
    @AppStorage(SystemDetectionSettings.capsLockIndicator)
    private var showsCapsLockIndicator = true
    @AppStorage(SystemDetectionSettings.capsLockLabel)
    private var showsCapsLockLabel = true
    @AppStorage(SystemDetectionSettings.capsLockColor)
    private var capsLockColorRaw = CapsLockIndicatorColor.blue.rawValue
    @AppStorage(NotchLayout.physicalNotchOutline)
    private var showsPhysicalNotchOutline = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var suppressedCompactPresentations:
        Set<CompactPresentation> = []
    @State private var keepsPausedCompactPresentation = false
    @State private var playbackLingerTask: Task<Void, Never>?

    private let expandedArtworkSize: CGFloat = 96
    private let expandedWatchFaceSize = NotchLayout.expandedContentHeight
    private let compactOuterPadding: CGFloat = 6

    private enum CompactPresentation: Hashable {
        case lock
        case unlock
        case device
        case activity(String)
        case playback
    }

    private var accent: Color {
        Color(nsColor: musicMonitor.snapshot?.accentColor ?? ArtworkPalette.fallback)
    }

    private var bottomBackground: Color {
        Color(
            nsColor: musicMonitor.snapshot?.bottomBackgroundColor
                ?? ArtworkPalette.fallback
        )
    }

    private var selectedNotchBackgroundEffect: NotchBackgroundEffect {
        NotchBackgroundEffect(rawValue: notchBackgroundEffectRaw) ?? .aurora
    }

    private var selectedProgressTrackStyle: ProgressTrackStyle {
        ProgressTrackStyle(rawValue: progressTrackStyleRaw) ?? .classic
    }

    var body: some View {
        let isPlaying = musicMonitor.snapshot?.isPlaying == true
        let deviceConnection = deviceConnectionMonitor.presentation
        let showsCompactActivity = compactPresentation != nil
        let systemHUDPresentation =
            deviceConnection == nil && !systemActivityMonitor.isScreenLocked
                ? systemHUDController.presentation
                : nil
        let showsNotchSideHUD = systemHUDPresentation != nil
            && selectedSystemHUDStyle == .island
        let showsExpandedHUD = systemHUDPresentation != nil
            && !showsNotchSideHUD
        let usesExpandedLayout =
            !showsNotchSideHUD && (panelState.isExpanded || showsExpandedHUD)
        let hasSystemHUD = systemHUDPresentation != nil
        let showsScreenStateIconOnly =
            !usesExpandedLayout
                && !showsNotchSideHUD
                && isScreenStateIconOnly
        let showsHoverPreview =
            panelState.isHoverPreviewActive
                && !usesExpandedLayout
                && !showsNotchSideHUD
        let hoverPreviewWidth: CGFloat = showsHoverPreview ? 18 : 0
        let hoverPreviewHeight: CGFloat = showsHoverPreview ? 4 : 0
        let size = CGSize(
            width: showsNotchSideHUD
                ? NotchLayout.sideHUDWidth(notchWidth: panelState.notchWidth)
                : usesExpandedLayout
                ? NotchLayout.expandedWidth(notchWidth: panelState.notchWidth)
                : NotchLayout.compactWidth(
                    notchWidth: panelState.notchWidth,
                    wingWidth: compactWingWidth
                ) + hoverPreviewWidth,
            height: showsNotchSideHUD
                ? panelState.topInset
                : usesExpandedLayout
                    ? NotchLayout.expandedHeight
                    : panelState.topInset + hoverPreviewHeight
        )
        let topCornerRadius: CGFloat = usesExpandedLayout
            ? 19
            : showsNotchSideHUD ? 10 : showsScreenStateIconOnly ? 0 : 6
        let bottomCornerRadius: CGFloat = usesExpandedLayout
            ? 24
            : showsNotchSideHUD ? 20 : showsScreenStateIconOnly ? 12 : 14
        let expandedArtworkOffset = CGPoint(
            x: NotchLayout.expandedHorizontalPadding,
            y: 42
        )

        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                NotchBackdrop(
                    topCornerRadius: topCornerRadius,
                    bottomCornerRadius: bottomCornerRadius,
                    artwork: musicMonitor.snapshot?.artwork,
                    accent: accent,
                    bottomBackground: bottomBackground,
                    isPlaying: isPlaying,
                    backgroundEnabled: notchBackgroundEnabled,
                    backgroundEffect: selectedNotchBackgroundEffect,
                    spectrumLevels: audioSpectrumMonitor.levels,
                    isExpanded: usesExpandedLayout,
                    topInset: panelState.topInset
                )

                if let snapshot = musicMonitor.snapshot,
                   let artwork = snapshot.artwork,
                   usesExpandedLayout,
                   !isPlaying,
                   selectedContentPage == .music {
                    ZStack(alignment: .topLeading) {
                        Color.clear

                        Image(nsImage: artwork)
                            .resizable()
                            .scaledToFill()
                            .frame(
                                width: expandedArtworkSize,
                                height: expandedArtworkSize
                            )
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 12,
                                    style: .continuous
                                )
                            )
                            .scaleEffect(1.24)
                            .saturation(1.45)
                            .contrast(1.06)
                            .brightness(0.06)
                            .blur(radius: 12)
                            .opacity(0.72)
                            .blendMode(.screen)
                            .offset(
                                x: expandedArtworkOffset.x,
                                y: expandedArtworkOffset.y
                            )
                    }
                    .id(snapshot.trackID)
                    .transition(.opacity)
                    .frame(width: size.width, height: size.height)
                    .mask {
                        Rectangle()
                            .overlay(alignment: .top) {
                                NotchShape(
                                    topCornerRadius: 0,
                                    bottomCornerRadius: 8
                                )
                                .frame(
                                    width: panelState.notchWidth,
                                    height: panelState.topInset
                                )
                                .blendMode(.destinationOut)
                            }
                            .compositingGroup()
                    }
                    .animation(
                        .easeInOut(duration: 0.46),
                        value: snapshot.trackID
                    )
                    .allowsHitTesting(false)
                }

                if showsNotchSideHUD, let presentation = systemHUDPresentation {
                    NotchSideSystemHUDView(
                        presentation: presentation,
                        albumAccent: accent,
                        notchWidth: panelState.notchWidth
                    )
                    .transition(
                        .opacity.combined(
                            with: .scale(scale: 0.97, anchor: .top)
                        )
                    )
                } else if usesExpandedLayout {
                    if let presentation = systemHUDPresentation,
                       showsExpandedHUD {
                        SystemHUDView(
                            presentation: presentation,
                            style: selectedSystemHUDStyle,
                            albumAccent: accent
                        )
                        .padding(.top, NotchLayout.expandedTopPadding)
                        .padding(.bottom, NotchLayout.expandedBottomPadding)
                        .transition(
                            .opacity.combined(
                                with: .scale(scale: 0.96, anchor: .top)
                            )
                        )
                    } else {
                        expandedPageContent(width: size.width)
                            .transition(expandedContentTransition)
                            .animation(
                                contentRevealAnimation,
                                value: panelState.isExpanded
                            )
                    }
                } else if showsCompactActivity {
                    compactContent(
                        deviceConnection: deviceConnection,
                        width: size.width,
                        cornerInset: topCornerRadius
                    )
                        .transition(.opacity)
                }

                if let snapshot = musicMonitor.snapshot,
                   !hasSystemHUD,
                   !systemActivityMonitor.isScreenLocked,
                   usesExpandedLayout || compactPresentation == .playback,
                   !usesExpandedLayout
                    || selectedContentPage == .music
                    || outgoingContentPage == .music {
                    let artworkSize: CGFloat = panelState.isExpanded
                        ? expandedArtworkSize
                        : 22
                    let artworkSwipeDistance = panelState.isExpanded
                        ? expandedArtworkSize + 12
                        : artworkSize + 8

                    ZStack {
                        artworkView(snapshot.artwork, size: artworkSize)
                            .id(snapshot.trackID)
                            .transition(
                                artworkTrackTransition(
                                    swipeDistance: artworkSwipeDistance
                                )
                            )
                    }
                    .frame(width: artworkSize, height: artworkSize)
                    .clipped()
                    .scaleEffect(
                        isPlaying || reduceMotion ? 1 : 0.95,
                        anchor: .center
                    )
                    .hoverParallax(
                        size: artworkSize,
                        isEnabled: usesExpandedLayout
                    )
                    .offset(
                        x: panelState.isExpanded
                            ? expandedArtworkOffset.x
                            : topCornerRadius + compactOuterPadding,
                        y: panelState.isExpanded
                            ? expandedArtworkOffset.y
                            : (size.height - artworkSize) / 2
                    )
                    .animation(
                        artworkAnimation,
                        value: panelState.isExpanded
                    )
                    .animation(
                        trackArtworkAnimation,
                        value: snapshot.trackID
                    )
                    .offset(
                        x: contentPageOffset(
                            for: .music,
                            width: size.width
                        )
                    )
                    .opacity(contentPageOpacity(for: .music))
                }

                if usesExpandedLayout && !hasSystemHUD {
                    expandedTrailingControls
                        .padding(.top, 9)
                        .padding(
                            .trailing,
                            NotchLayout.expandedHorizontalPadding
                        )
                        .frame(
                            width: size.width,
                            height: size.height,
                            alignment: .topTrailing
                        )

                    expandedPageSwitcher
                        .padding(.top, 9)
                        .padding(
                            .leading,
                            NotchLayout.expandedHorizontalPadding
                        )
                        .frame(
                            width: size.width,
                            height: size.height,
                            alignment: .topLeading
                        )
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(
                NotchShape(
                    topCornerRadius: topCornerRadius,
                    bottomCornerRadius: bottomCornerRadius
                )
            )
            .background {
                NotchShape(
                    topCornerRadius: topCornerRadius,
                    bottomCornerRadius: bottomCornerRadius
                )
                .fill(Color.black.opacity(0.30))
                .frame(width: size.width, height: size.height)
                .blur(radius: 16)
                .offset(y: 2)
                .opacity(
                    panelState.isHovering || panelState.isExpanded ? 1 : 0
                )
                .allowsHitTesting(false)
            }
            .shadow(
                color: .black.opacity(
                    panelState.isHovering || panelState.isExpanded ? 0.70 : 0
                ),
                radius: 20,
                y: 2
            )
            .overlay {
                NotchShape(
                    topCornerRadius: topCornerRadius,
                    bottomCornerRadius: bottomCornerRadius
                )
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            }
            .overlay(alignment: .topLeading) {
                if showsPhysicalNotchOutline {
                    physicalNotchOutline(width: size.width)
                }
            }
            .contentShape(
                NotchShape(
                    topCornerRadius: topCornerRadius,
                    bottomCornerRadius: bottomCornerRadius
                )
            )
            .onHover { hovering in
                guard !systemActivityMonitor.isScreenLocked else { return }
                panelState.setHovering(hovering)
            }
            .gesture(
                TapGesture().onEnded {
                    panelState.expand()
                },
                including: usesExpandedLayout
                    || systemActivityMonitor.isScreenLocked
                    ? .none
                    : .all
            )

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(
            .spring(response: 0.24, dampingFraction: 0.64),
            value: panelState.isHoverPreviewActive
        )
        .animation(
            .easeOut(duration: 0.18),
            value: panelState.isHovering
        )
        .animation(
            expansionAnimation,
            value: panelState.isExpanded
        )
        .animation(
            .spring(response: 0.34, dampingFraction: 0.9),
            value: isPlaying
        )
        .animation(
            systemActivityAnimation,
            value: systemActivitySignature
        )
        .animation(
            .spring(response: 0.32, dampingFraction: 0.84),
            value: systemHUDController.presentation
        )
        .animation(
            compactPresentationAnimation,
            value: compactPresentation
        )
        .task(id: suppressibleCompactPresentation) {
            guard let presentation = suppressibleCompactPresentation else {
                return
            }
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            suppressedCompactPresentations.insert(presentation)
        }
        .onChange(of: activeCompactPresentations) { _, presentations in
            suppressedCompactPresentations.formIntersection(presentations)
        }
        .onChange(of: systemActivityMonitor.isScreenLocked) { _, isLocked in
            suppressedCompactPresentations.removeAll()
            guard !isLocked else { return }
            suppressedCompactPresentations.formUnion(
                compactSystemActivities
                    .filter {
                        $0.id != "screenState"
                            && $0.id != "microphone"
                    }
                    .map { .activity($0.id) }
            )
        }
        .onChange(of: musicMonitor.snapshot?.isPlaying) { wasPlaying, isPlaying in
            guard isPlaying == false, wasPlaying == true else {
                if isPlaying == true {
                    playbackLingerTask?.cancel()
                    playbackLingerTask = nil
                    keepsPausedCompactPresentation = false
                }
                return
            }

            playbackLingerTask?.cancel()
            keepsPausedCompactPresentation = true
            playbackLingerTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                keepsPausedCompactPresentation = false
            }
        }
    }

    private var expansionAnimation: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.18)
        }

        // iOS 18-style expansion: slightly slower with a more visible bounce.
        // Collapsing keeps just enough damping to avoid dipping below the
        // physical notch height.
        return panelState.isExpanded
            ? .spring(response: 0.44, dampingFraction: 0.68, blendDuration: 0)
            : .spring(response: 0.44, dampingFraction: 0.96, blendDuration: 0)
    }

    private var systemActivityAnimation: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.18)
        }
        return .spring(
            response: 0.40,
            dampingFraction: 0.92,
            blendDuration: 0.08
        )
    }

    private var compactCarouselAnimation: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.18)
        }
        return .spring(
            response: 0.32,
            dampingFraction: 0.64,
            blendDuration: 0.04
        )
    }

    private var expandedContentTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }

        return .asymmetric(
            insertion: AnyTransition.modifier(
                active: NotchBlurTransitionModifier(radius: 7),
                identity: NotchBlurTransitionModifier(radius: 0)
            )
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.82, anchor: .center)),
            removal: .opacity.combined(
                with: .scale(scale: 0.985, anchor: .top)
            )
        )
    }

    private var contentRevealAnimation: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.18)
        }

        if panelState.isExpanded {
            return .easeOut(duration: 0.42).delay(0.04)
        }
        return .easeIn(duration: 0.14)
    }

    private var compactSceneTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }

        return .asymmetric(
            insertion: AnyTransition.modifier(
                active: NotchBlurTransitionModifier(radius: 2),
                identity: NotchBlurTransitionModifier(radius: 0)
            )
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.74, anchor: .center)),
            removal: .opacity.combined(
                with: .scale(scale: 0.86, anchor: .center)
            )
        )
    }

    private var compactPresentationAnimation: Animation {
        guard let presentation = compactPresentation else {
            return systemActivityAnimation
        }
        switch presentation {
        case .unlock, .device, .activity:
            return compactCarouselAnimation
        case .lock, .playback:
            return systemActivityAnimation
        }
    }

    /// The artwork travels a much larger relative distance than the panel, so
    /// the panel spring's long tail stays visible on the cover after the notch
    /// has already settled. Match the panel's visible settle time instead.
    private var artworkAnimation: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.18)
        }

        return expansionAnimation
    }

    private var trackArtworkAnimation: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.12)
        }

        return .spring(
            response: 0.32,
            dampingFraction: 0.92,
            blendDuration: 0
        )
    }

    private func artworkTrackTransition(
        swipeDistance: CGFloat
    ) -> AnyTransition {
        guard !reduceMotion else { return .opacity }

        let insertionOffset =
            musicMonitor.trackTransitionDirection == .forward
                ? swipeDistance
                : -swipeDistance
        let scale: CGFloat = 0.96
        return .asymmetric(
            insertion: .offset(x: insertionOffset)
                .combined(with: .scale(scale: scale))
                .combined(with: .opacity),
            removal: .offset(x: -insertionOffset)
                .combined(with: .scale(scale: scale))
                .combined(with: .opacity)
        )
    }

    /// Dashed outline of the physical camera notch, drawn relative to the
    /// panel so the gap against the virtual notch stays visible.
    private func physicalNotchOutline(width: CGFloat) -> some View {
        let panelOriginX = panelState.screenCenterX - width / 2
        let leading = panelState.notchLeading - panelOriginX
        let trailing = panelState.notchTrailing - panelOriginX
        let height = panelState.topInset
        let cornerRadius: CGFloat = 8

        return ZStack(alignment: .topLeading) {
            Path { path in
                let rectWidth = max(trailing - leading, 1)

                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: rectWidth, y: 0))
                path.addLine(
                    to: CGPoint(x: rectWidth, y: height - cornerRadius)
                )
                path.addQuadCurve(
                    to: CGPoint(x: rectWidth - cornerRadius, y: height),
                    control: CGPoint(x: rectWidth, y: height)
                )
                path.addLine(
                    to: CGPoint(x: cornerRadius, y: height)
                )
                path.addQuadCurve(
                    to: CGPoint(x: 0, y: height - cornerRadius),
                    control: CGPoint(x: 0, y: height)
                )
                path.closeSubpath()
            }
            .stroke(
                Color.white.opacity(0.85),
                style: StrokeStyle(
                    lineWidth: 0.75
                )
            )
            .frame(
                width: max(trailing - leading, 1),
                height: height
            )
            .offset(x: leading)
        }
            .frame(width: width, height: height, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func compactContent(
        deviceConnection: DeviceConnectionPresentation?,
        width: CGFloat,
        cornerInset: CGFloat
    ) -> some View {
        let wingWidth = max(
            0,
            (width - compactPhysicalNotchWidth) / 2
        )
        let innerWingWidth = max(0, wingWidth - cornerInset)

        return HStack(spacing: 0) {
            Group {
                switch compactPresentation {
                case .lock, .unlock:
                    if let activity = compactScreenStateActivity {
                        compactActivityIcon(activity)
                            .transition(compactSceneTransition)
                    }
                case .device:
                    if let deviceConnection {
                        AirPodsStatusIcon(
                            model: deviceConnection.model,
                            size: 30
                        )
                            .transition(compactSceneTransition)
                    }
                case .activity(let id):
                    if let activity = compactSystemActivities.first(
                        where: { $0.id == id }
                    ) {
                        compactActivityIcon(activity)
                            .transition(compactSceneTransition)
                    }
                case .playback, nil:
                    Color.clear
                }
            }
            .padding(.leading, compactOuterPadding)
            .frame(width: innerWingWidth, alignment: .leading)
            .padding(.leading, cornerInset)

            Color.clear
                .frame(width: compactPhysicalNotchWidth)

            HStack(spacing: 5) {
                switch compactPresentation {
                case .device:
                    if let deviceConnection {
                        CompactVolumeRing(
                            level: deviceConnectionVolumeLevel(deviceConnection)
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("AirPods 音量")
                        .accessibilityValue(
                            deviceConnectionVolumeText(deviceConnection)
                        )
                        .transition(compactSceneTransition)
                    }
                case .activity(let id):
                    if let activity = compactSystemActivities.first(
                        where: { $0.id == id }
                    ), let name = activity.name {
                        Text(name)
                            .font(
                                .system(
                                    size: 10.5,
                                    weight: .semibold,
                                    design: .rounded
                                )
                            )
                            .foregroundStyle(activity.tint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .transition(compactSceneTransition)
                    }
                case .playback:
                    CompactPlaybackIndicator(
                        color: bottomBackground,
                        levels: audioSpectrumMonitor.levels
                    )
                case .lock, .unlock, nil:
                    Color.clear
                }
            }
            .padding(.trailing, compactOuterPadding)
            .frame(width: innerWingWidth, alignment: .trailing)
            .padding(.trailing, cornerInset)
        }
        .frame(maxHeight: .infinity)
        .help(compactHelpText(deviceConnection: deviceConnection))
    }

    private func compactHelpText(
        deviceConnection: DeviceConnectionPresentation?
    ) -> String {
        switch compactPresentation {
        case .lock:
            return "屏幕已锁定"
        case .unlock:
            return "屏幕已解锁"
        case .device:
            return deviceConnection.map {
                "\($0.deviceName) 已连接"
            } ?? ""
        case .activity(let id):
            return compactSystemActivities.first {
                $0.id == id
            }?.accessibilityLabel ?? ""
        case .playback:
            return "正在播放"
        case nil:
            return ""
        }
    }

    private func deviceConnectionVolumeText(
        _ presentation: DeviceConnectionPresentation
    ) -> String {
        if presentation.isMuted {
            return "0%"
        }
        guard let volume = presentation.volume else { return "--" }
        return "\(Int((volume * 100).rounded()))%"
    }

    private func deviceConnectionVolumeLevel(
        _ presentation: DeviceConnectionPresentation
    ) -> Double {
        guard !presentation.isMuted,
              let volume = presentation.volume else {
            return 0
        }
        return min(max(volume, 0), 1)
    }

    private var compactFocusText: String {
        let name = systemActivityMonitor.focusName
        if name.isEmpty {
            return "专注"
        }
        return usesCompactFocusHint ? name : "专注 · \(name)"
    }

    private func compactActivityIcon(
        _ activity: CompactSystemActivity
    ) -> some View {
        let iconSize: CGFloat =
            activity.id == "screenState"
                ? 12.5
                : 11

        return Image(systemName: activity.icon)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(activity.tint)
            .frame(width: 16, height: 16)
            .contentTransition(.symbolEffect(.replace))
            .animation(.easeInOut(duration: 0.22), value: activity.icon)
            .accessibilityLabel(activity.accessibilityLabel)
    }

    private var compactSystemActivities: [CompactSystemActivity] {
        var activities: [CompactSystemActivity] = []

        if systemActivityMonitor.isScreenLocked {
            return [
                CompactSystemActivity(
                    id: "screenState",
                    icon: "lock.fill",
                    name: nil,
                    tint: Color.white.opacity(0.88),
                    accessibilityLabel: "屏幕已锁定"
                )
            ]
        } else if systemActivityMonitor.showsUnlockConfirmation {
            activities.append(
                CompactSystemActivity(
                    id: "screenState",
                    icon: "lock.open.fill",
                    name: nil,
                    tint: Color.white.opacity(0.88),
                    accessibilityLabel: "屏幕已解锁"
                )
            )
        }

        if showsScreenRecordingIndicator && systemActivityMonitor.isScreenRecording {
            activities.append(
                CompactSystemActivity(
                    id: "screenRecording",
                    icon: "record.circle.fill",
                    name: "屏幕录制",
                    tint: Color(red: 0.82, green: 0.40, blue: 1.0),
                    accessibilityLabel: "正在录制屏幕"
                )
            )
        }

        if showsFocusIndicator && systemActivityMonitor.isFocusActive {
            activities.append(
                CompactSystemActivity(
                    id: "focus",
                    icon: "moon.fill",
                    name: showsFocusLabel ? compactFocusText : nil,
                    tint: Color(red: 0.64, green: 0.53, blue: 1.0),
                    accessibilityLabel: "专注模式 \(systemActivityMonitor.focusName)"
                )
            )
        }

        if systemActivityMonitor.isCameraActive {
            activities.append(
                CompactSystemActivity(
                    id: "camera",
                    icon: "video.fill",
                    name: "相机",
                    tint: Color(red: 0.27, green: 0.85, blue: 0.58),
                    accessibilityLabel: "相机正在使用"
                )
            )
        }

        if systemActivityMonitor.isMicrophoneActive {
            activities.append(
                CompactSystemActivity(
                    id: "microphone",
                    icon: "mic.fill",
                    name: "麦克风",
                    tint: Color(red: 1.0, green: 0.68, blue: 0.25),
                    accessibilityLabel: "麦克风正在使用"
                )
            )
        }

        if showsCapsLockIndicator && systemActivityMonitor.isCapsLockOn {
            activities.append(
                CompactSystemActivity(
                    id: "capsLock",
                    icon: "capslock.fill",
                    name: showsCapsLockLabel ? "Caps Lock" : nil,
                    tint: capsLockColor,
                    accessibilityLabel: "Caps Lock 已开启"
                )
            )
        }

        return activities
    }

    private func activityIcon(
        _ systemName: String,
        tint: Color,
        label: String
    ) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 16, height: 16)
            .background(tint.opacity(0.15), in: Circle())
            .accessibilityLabel(label)
    }

    private var expandedSystemActivity: some View {
        HStack(spacing: 5) {
            if systemActivityMonitor.isScreenLocked {
                activityIcon(
                    "lock.fill",
                    tint: Color(red: 0.76, green: 0.82, blue: 0.96),
                    label: "屏幕已锁定"
                )
            } else if systemActivityMonitor.showsUnlockConfirmation {
                activityIcon(
                    "lock.open.fill",
                    tint: Color(red: 0.33, green: 0.86, blue: 0.61),
                    label: "屏幕已解锁"
                )
            }

            if showsScreenRecordingIndicator && systemActivityMonitor.isScreenRecording {
                activityIcon(
                    "record.circle.fill",
                    tint: Color(red: 0.82, green: 0.40, blue: 1.0),
                    label: "正在录制屏幕"
                )
            }

            if showsFocusIndicator && systemActivityMonitor.isFocusActive {
                activityIcon(
                    "moon.fill",
                    tint: Color(red: 0.64, green: 0.53, blue: 1.0),
                    label: "专注模式"
                )
            }

            if systemActivityMonitor.isCameraActive {
                activityIcon(
                    "video.fill",
                    tint: Color(red: 0.27, green: 0.85, blue: 0.58),
                    label: "相机正在使用"
                )
            }

            if systemActivityMonitor.isMicrophoneActive {
                activityIcon(
                    "mic.fill",
                    tint: Color(red: 1.0, green: 0.68, blue: 0.25),
                    label: "麦克风正在使用"
                )
            }

            if showsCapsLockIndicator && systemActivityMonitor.isCapsLockOn {
                activityIcon(
                    "capslock.fill",
                    tint: capsLockColor,
                    label: "Caps Lock 已开启"
                )
            }
        }
    }

    private var expandedTrailingControls: some View {
        HStack(spacing: 8) {
            if systemActivityIconCount > 0 {
                expandedSystemActivity
            }

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("设置")
            .accessibilityLabel("打开设置")
        }
        .frame(height: 24, alignment: .center)
    }

    private var expandedPageSwitcher: some View {
        HStack(spacing: 1) {
            ForEach(NotchContentPage.allCases) { page in
                let isSelected = selectedContentPage == page

                Button {
                    guard page != selectedContentPage,
                          outgoingContentPage == nil else {
                        return
                    }
                    let currentIndex =
                        NotchContentPage.allCases.firstIndex(
                            of: selectedContentPage
                        ) ?? 0
                    let targetIndex =
                        NotchContentPage.allCases.firstIndex(
                            of: page
                        ) ?? currentIndex

                    contentPageTransitionDirection =
                        targetIndex > currentIndex
                            ? .forward
                            : .backward
                    outgoingContentPage = selectedContentPage
                    contentPageTransitionProgress = 0
                    selectedContentPage = page
                    pageSwitchTask?.cancel()
                    pageSwitchTask = Task { @MainActor in
                        try? await Task.sleep(
                            nanoseconds: 16_000_000
                        )
                        guard !Task.isCancelled else { return }

                        withAnimation(contentPageAnimation) {
                            contentPageTransitionProgress = 1
                        }
                        try? await Task.sleep(
                            nanoseconds: reduceMotion
                                ? 220_000_000
                                : 600_000_000
                        )
                        guard !Task.isCancelled else { return }

                        outgoingContentPage = nil
                        contentPageTransitionProgress = 1
                    }
                } label: {
                    Image(systemName: page.systemImage)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(
                            isSelected
                                ? Color.white
                                : Color.white.opacity(0.42)
                        )
                        .frame(width: 24, height: 20)
                        .background(
                            isSelected
                                ? accent.opacity(0.34)
                                : Color.clear,
                            in: Capsule()
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(page.title)
                .accessibilityLabel(page.title)
            }
        }
        .padding(2)
        .background(
            Color.white.opacity(0.055),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
        }
    }

    private var hasSystemActivityIndicator: Bool {
        systemActivityIconCount > 0
    }

    private var systemActivityIconCount: Int {
        var count = 0
        if systemActivityMonitor.isScreenLocked
            || systemActivityMonitor.showsUnlockConfirmation {
            count += 1
        }
        if showsScreenRecordingIndicator && systemActivityMonitor.isScreenRecording {
            count += 1
        }
        if showsFocusIndicator && systemActivityMonitor.isFocusActive {
            count += 1
        }
        if systemActivityMonitor.isCameraActive {
            count += 1
        }
        if systemActivityMonitor.isMicrophoneActive {
            count += 1
        }
        if showsCapsLockIndicator && systemActivityMonitor.isCapsLockOn {
            count += 1
        }
        return count
    }

    private var activeCompactPresentations: [CompactPresentation] {
        guard !systemActivityMonitor.isScreenLocked else { return [] }

        var presentations: [CompactPresentation] = []
        if systemActivityMonitor.showsUnlockConfirmation {
            presentations.append(.unlock)
        }
        if deviceConnectionMonitor.presentation != nil {
            presentations.append(.device)
        }
        presentations.append(
            contentsOf: compactSystemActivities
                .filter {
                    $0.id != "screenState"
                        && $0.id != "microphone"
                }
                .map { .activity($0.id) }
        )
        return presentations
    }

    private var compactPresentation: CompactPresentation? {
        if systemActivityMonitor.isScreenLocked {
            return .lock
        }
        if let presentation = activeCompactPresentations.first(
            where: { !suppressedCompactPresentations.contains($0) }
        ) {
            return presentation
        }
        if musicMonitor.snapshot?.isPlaying == true
            || keepsPausedCompactPresentation {
            return .playback
        }
        return nil
    }

    private var suppressibleCompactPresentation: CompactPresentation? {
        guard compactPresentation != .lock,
              compactPresentation != .playback else {
            return nil
        }
        return compactPresentation
    }

    private var compactScreenStateActivity: CompactSystemActivity? {
        compactSystemActivities.first { $0.id == "screenState" }
    }

    private var compactPhysicalNotchWidth: CGFloat {
        let measured = panelState.notchTrailing - panelState.notchLeading
        return measured > 0 ? measured : panelState.notchWidth
    }

    private var compactWingWidth: CGFloat {
        guard let presentation = compactPresentation else { return 0 }

        switch presentation {
        case .lock, .unlock:
            return 34
        case .device:
            return 48
        case .activity(let id):
            let label = compactSystemActivities.first {
                $0.id == id
            }?.name
            let labelWidth = label.map(compactLabelWidth) ?? 0
            return min(max(16, labelWidth) + 16, 170)
        case .playback:
            return 38
        }
    }

    private var isScreenStateIconOnly: Bool {
        compactPresentation == .lock || compactPresentation == .unlock
    }

    private func compactLabelWidth(_ text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    private var capsLockColor: Color {
        (CapsLockIndicatorColor(rawValue: capsLockColorRaw) ?? .blue).color
    }

    private var systemActivitySignature: String {
        [
            String(systemActivityMonitor.isScreenRecording),
            String(systemActivityMonitor.isFocusActive),
            systemActivityMonitor.focusName,
            String(systemActivityMonitor.isCapsLockOn),
            String(systemActivityMonitor.isCameraActive),
            String(systemActivityMonitor.isMicrophoneActive),
            String(systemActivityMonitor.isScreenLocked),
            String(systemActivityMonitor.showsUnlockConfirmation),
            String(showsScreenRecordingIndicator),
            String(showsFocusIndicator),
            String(showsFocusLabel),
            String(usesCompactFocusHint),
            String(showsCapsLockIndicator),
            String(showsCapsLockLabel),
            capsLockColorRaw
        ].joined(separator: "|")
    }

    private var contentPageAnimation: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.15)
        }
        return .spring(
            response: 0.34,
            dampingFraction: 0.84,
            blendDuration: 0.05
        )
    }

    @ViewBuilder
    private func expandedContent(
        for page: NotchContentPage,
        width: CGFloat
    ) -> some View {
        if page == .music {
            expandedMusicContent(width: width)
        } else {
            CalendarIslandView(accent: accent)
                .padding(
                    .horizontal,
                    NotchLayout.expandedHorizontalPadding
                )
                .padding(.top, NotchLayout.expandedTopPadding)
                .padding(.bottom, NotchLayout.expandedBottomPadding)
        }
    }

    private func expandedPageContent(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if let outgoingContentPage {
                expandedContent(
                    for: outgoingContentPage,
                    width: width
                )
                .offset(
                    x: contentPageOffset(
                        for: outgoingContentPage,
                        width: width
                    )
                )
                .opacity(
                    contentPageOpacity(for: outgoingContentPage)
                )
            }

            expandedContent(
                for: selectedContentPage,
                width: width
            )
            .offset(
                x: contentPageOffset(
                    for: selectedContentPage,
                    width: width
                )
            )
            .opacity(
                contentPageOpacity(for: selectedContentPage)
            )
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .clipped()
        .allowsHitTesting(outgoingContentPage == nil)
    }

    private func contentPageOffset(
        for page: NotchContentPage,
        width: CGFloat
    ) -> CGFloat {
        guard !reduceMotion,
              outgoingContentPage != nil else {
            return 0
        }

        let direction: CGFloat =
            contentPageTransitionDirection == .forward ? 1 : -1
        let progress = min(max(contentPageTransitionProgress, 0), 1)

        if page == selectedContentPage {
            return direction * width * (1 - progress)
        }
        if page == outgoingContentPage {
            return -direction * width * progress
        }
        return 0
    }

    private func contentPageOpacity(
        for page: NotchContentPage
    ) -> Double {
        guard outgoingContentPage != nil else { return 1 }

        let progress = min(max(contentPageTransitionProgress, 0), 1)
        if page == selectedContentPage {
            return Double(progress)
        }
        if page == outgoingContentPage {
            return Double(1 - progress)
        }
        return 1
    }

    private func expandedMusicContent(width: CGFloat) -> some View {
        let musicWidth = max(
            0,
            width
                - NotchLayout.expandedHorizontalPadding * 2
                - NotchLayout.expandedColumnSpacing
                - expandedWatchFaceSize
        )

        return HStack(
            alignment: .top,
            spacing: NotchLayout.expandedColumnSpacing
        ) {
            Group {
                if let snapshot = musicMonitor.snapshot {
                    nowPlaying(snapshot)
                } else {
                    emptyState
                }
            }
            .frame(width: musicWidth)
            .frame(maxHeight: .infinity, alignment: .topLeading)

            WatchFaceView(
                style: selectedWatchFace,
                accent: accent,
                size: expandedWatchFaceSize
            )
            .hoverParallax(size: expandedWatchFaceSize)
        }
        .padding(.horizontal, NotchLayout.expandedHorizontalPadding)
        .padding(.top, NotchLayout.expandedTopPadding)
        .padding(.bottom, NotchLayout.expandedBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .compositingGroup()
    }

    private var selectedWatchFace: WatchFaceStyle {
        WatchFaceStyle(rawValue: watchFaceStyleRaw) ?? .classic
    }

    private var selectedSystemHUDStyle: SystemHUDStyle {
        SystemHUDStyle(rawValue: systemHUDStyleRaw) ?? .island
    }

    private func nowPlaying(_ snapshot: MusicSnapshot) -> some View {
        let rowHeight = expandedArtworkSize / 4

        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Color.clear
                    .frame(
                        width: expandedArtworkSize,
                        height: expandedArtworkSize
                    )

                VStack(alignment: .leading, spacing: 0) {
                    OverflowMarqueeText(
                        text: snapshot.title,
                        font: PixelTypography.font(size: 18),
                        color: .white,
                        speed: 32
                    )
                    .frame(height: rowHeight)

                    OverflowMarqueeText(
                        text: snapshot.artist.isEmpty
                            ? "Apple Music"
                            : snapshot.artist,
                        font: PixelTypography.font(size: 12),
                        color: .white.opacity(0.72)
                    )
                    .frame(height: rowHeight)

                    OverflowMarqueeText(
                        text: snapshot.album.isEmpty ? " " : snapshot.album,
                        font: PixelTypography.font(size: 12),
                        color: .white.opacity(0.42)
                    )
                    .frame(height: rowHeight)

                    playbackControls(snapshot)
                        .frame(height: rowHeight)
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: expandedArtworkSize,
                    maxHeight: expandedArtworkSize,
                    alignment: .topLeading
                )
            }
            .frame(height: expandedArtworkSize, alignment: .top)

            Spacer(minLength: 6)

            playbackProgress(snapshot)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func playbackProgress(_ snapshot: MusicSnapshot) -> some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: !snapshot.isPlaying
            )
        ) { context in
            let elapsed = snapshot.elapsed(at: context.date)
            let displayedPosition = scrubPosition ?? elapsed

            VStack(spacing: 4) {
                AccentProgressSlider(
                    value: displayedPosition,
                    range: 0...max(snapshot.duration, 1),
                    color: Color(nsColor: snapshot.bottomBackgroundColor),
                    style: selectedProgressTrackStyle,
                    isPlaying: snapshot.isPlaying,
                    isEnabled: snapshot.duration > 0 && !musicMonitor.isSendingCommand,
                    onChange: { scrubPosition = $0 },
                    onEditingStarted: {
                        if scrubPosition == nil {
                            scrubPosition = elapsed
                        }
                    },
                    onCommit: { position in
                        musicMonitor.seek(to: position)
                        scrubPosition = nil
                    }
                )

                HStack {
                    Text(timeString(displayedPosition))
                    Spacer()
                    Text(timeString(snapshot.duration))
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.42))
            }
        }
    }

    private func playbackControls(_ snapshot: MusicSnapshot) -> some View {
        let layout = MusicControlLayoutSettings.decode(musicControlLayoutRaw)
        let items = layout.compactMap { $0 }

        return HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                musicControlContent(item, snapshot: snapshot)
                    .frame(minHeight: 28)
                    .offset(
                        x: index == 0
                            ? (item == .shuffle ? -7 : -5)
                            : 0
                    )

                if index < items.count - 1 {
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .onChange(of: musicControlLayoutRaw) { _, rawValue in
            if !MusicControlLayoutSettings.decode(rawValue).contains(.volume) {
                showsVolumeSlider = false
            }
        }
        .disabled(musicMonitor.isSendingCommand)
        .opacity(musicMonitor.isSendingCommand ? 0.55 : 1)
    }

    @ViewBuilder
    private func musicControlContent(
        _ item: MusicControlItem,
        snapshot: MusicSnapshot
    ) -> some View {
        switch item {
        case .shuffle:
            PlaybackButton(
                systemName: "shuffle",
                label: snapshot.isShuffleEnabled ? "关闭随机播放" : "开启随机播放",
                tint: bottomBackground,
                activeTint: accent,
                isActive: snapshot.isShuffleEnabled,
                action: musicMonitor.toggleShuffle
            )

        case .previous:
            PlaybackButton(
                systemName: "backward.fill",
                label: "上一首",
                tint: bottomBackground,
                action: musicMonitor.previousTrack
            )

        case .playPause:
            PlaybackButton(
                systemName: snapshot.isPlaying ? "pause.fill" : "play.fill",
                label: snapshot.isPlaying ? "暂停" : "播放",
                tint: bottomBackground,
                activeTint: accent,
                emphasized: true,
                isActive: snapshot.isPlaying,
                action: musicMonitor.togglePlayPause
            )

        case .next:
            PlaybackButton(
                systemName: "forward.fill",
                label: "下一首",
                tint: bottomBackground,
                action: musicMonitor.nextTrack
            )

        case .volume:
            HStack(spacing: 3) {
                PlaybackButton(
                    systemName: volumeIcon(snapshot.volume),
                    label: "音量",
                    tint: bottomBackground,
                    fontSize: 12
                ) {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showsVolumeSlider.toggle()
                    }
                }

                if showsVolumeSlider {
                    Slider(
                        value: Binding(
                            get: { snapshot.volume },
                            set: { musicMonitor.setVolume($0) }
                        ),
                        in: 0...1
                    )
                    .controlSize(.mini)
                    .tint(bottomBackground)
                    .frame(width: 42)
                    .accessibilityLabel("Apple Music 音量")
                    .transition(
                        .opacity.combined(
                            with: .scale(scale: 0.85, anchor: .trailing)
                        )
                    )
                }
            }
        }
    }

    private func volumeIcon(_ volume: Double) -> String {
        if volume == 0 {
            return "speaker.slash.fill"
        }
        if volume < 0.33 {
            return "speaker.1.fill"
        }
        if volume < 0.66 {
            return "speaker.2.fill"
        }
        return "speaker.3.fill"
    }

    private func artworkView(_ artwork: NSImage?, size: CGFloat) -> some View {
        Group {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.15),
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Image(systemName: "music.note")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white.opacity(0.56))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(
            RoundedRectangle(
                cornerRadius: panelState.isExpanded ? 12 : 6,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: panelState.isExpanded ? 12 : 6,
                style: .continuous
            )
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        }
    }

    private var emptyState: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.08))

                Image(systemName: stateIcon)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(.white.opacity(0.66))
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 5) {
                Text(stateTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text(stateDescription)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.54))
                    .lineLimit(2)

                if let primaryAction {
                    Button(primaryAction.title, action: primaryAction.action)
                        .buttonStyle(NotchActionButtonStyle())
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var stateTitle: String {
        if !musicMonitor.isConnected {
            return "连接 Apple Music"
        }
        if musicMonitor.needsPermission {
            return "需要自动化权限"
        }
        if !musicMonitor.isMusicRunning {
            return "Apple Music 未运行"
        }
        if musicMonitor.errorMessage != nil {
            return "读取失败"
        }
        return "没有正在播放的音乐"
    }

    private var stateDescription: String {
        if !musicMonitor.isConnected {
            return "授权后，刘海会显示当前播放的歌曲。"
        }
        if musicMonitor.needsPermission {
            return "在系统设置中允许 NotchMusic 控制 Apple Music。"
        }
        if !musicMonitor.isMusicRunning {
            return "播放音乐后会自动显示在这里。"
        }
        if let errorMessage = musicMonitor.errorMessage {
            return errorMessage
        }
        return "在 Apple Music 中选择一首歌曲。"
    }

    private var stateIcon: String {
        if !musicMonitor.isConnected {
            return "link"
        }
        if musicMonitor.needsPermission {
            return "lock.open"
        }
        if !musicMonitor.isMusicRunning {
            return "music.note"
        }
        if musicMonitor.errorMessage != nil {
            return "exclamationmark.triangle"
        }
        return "waveform"
    }

    private var primaryAction: (title: String, action: () -> Void)? {
        if !musicMonitor.isConnected {
            return ("连接", { musicMonitor.connect() })
        }
        if musicMonitor.needsPermission {
            return ("打开系统设置", { musicMonitor.openAutomationSettings() })
        }
        if !musicMonitor.isMusicRunning {
            return ("打开 Apple Music", { musicMonitor.openAppleMusic() })
        }
        if musicMonitor.errorMessage != nil {
            return ("重试", { musicMonitor.refreshNow() })
        }
        return ("刷新", { musicMonitor.refreshNow() })
    }

    private func timeString(_ value: TimeInterval) -> String {
        guard value.isFinite, value >= 0 else { return "0:00" }
        let total = Int(value.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct OverflowMarqueeText: View {
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
                    .animation(minimumInterval: 1.0 / 30.0)
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

private struct AccentProgressSlider: View {
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
                minimumInterval: 1.0 / 30.0,
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
                minimumInterval: 1.0 / 30.0,
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
                    let phase = fraction(
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

    private func fraction(_ value: Double) -> Double {
        value - floor(value)
    }
}

private struct NotchBackdrop: View {
    let topCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat
    let artwork: NSImage?
    let accent: Color
    let bottomBackground: Color
    let isPlaying: Bool
    let backgroundEnabled: Bool
    let backgroundEffect: NotchBackgroundEffect
    let spectrumLevels: [CGFloat]
    let isExpanded: Bool
    let topInset: CGFloat

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

                if isPlaying && backgroundEnabled {
                    NotchBackgroundView(
                        effect: backgroundEffect,
                        accent: bottomBackground,
                        spectrumLevels: spectrumLevels
                    )
                        .transition(.opacity)
                }

                VStack(spacing: 0) {
                    Color.black
                        .frame(height: topInset + 1)

                    LinearGradient(
                        colors: [
                            .black,
                            .black.opacity(0.72),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 24)

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
    }
}

private struct NotchBackgroundView: View {
    let effect: NotchBackgroundEffect
    let accent: Color
    let spectrumLevels: [CGFloat]

    @ViewBuilder
    var body: some View {
        switch effect {
        case .aurora:
            AuroraGlow(accent: accent)
        case .gradientWaves:
            GradientWavesBackground(accent: accent)
        case .aeroShards:
            AeroShardsBackground(accent: accent)
        case .pixelMatrix:
            PixelMatrixBackground(accent: accent)
        case .spectrum:
            SpectrumBackground(
                levels: spectrumLevels,
                accent: accent
            )
        default:
            ProceduralNotchBackground(
                effect: effect,
                accent: accent
            )
        }
    }
}

private struct SpectrumBackground: View {
    let levels: [CGFloat]
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: reduceMotion
            )
        ) { timeline in
            GeometryReader { geometry in
                ZStack {
                    RadialGradient(
                        colors: [
                            accent.opacity(0.24),
                            accent.opacity(0.08),
                            .clear
                        ],
                        center: .bottom,
                        startRadius: 4,
                        endRadius: max(geometry.size.width * 0.72, 180)
                    )

                    Canvas { context, size in
                        guard size.width > 0, size.height > 0 else { return }

                        let time = timeline.date.timeIntervalSinceReferenceDate
                        let usesLiveLevels = levels.contains { $0 > 0.015 }
                        let barCount = 52
                        let gap: CGFloat = 2
                        let barWidth = max(
                            1.5,
                            (size.width - CGFloat(barCount - 1) * gap)
                                / CGFloat(barCount)
                        )
                        let maximumHeight = size.height * 0.72
                        let bars = (0..<barCount).map { index in
                            let distance = abs(
                                CGFloat(index) / CGFloat(barCount - 1) - 0.5
                            ) * 2
                            let envelope = CGFloat(
                                pow(Double(max(0, 1 - distance)), 0.55)
                            )
                            let value = level(
                                at: index,
                                count: barCount,
                                time: time,
                                usesLiveLevels: usesLiveLevels
                            )
                            let height = max(
                                2,
                                maximumHeight
                                    * CGFloat(pow(Double(value), 0.72))
                                    * (0.30 + envelope * 0.70)
                            )
                            let rect = CGRect(
                                x: CGFloat(index) * (barWidth + gap),
                                y: size.height - height,
                                width: barWidth,
                                height: height
                            )
                            return (
                                path: Path(
                                    roundedRect: rect,
                                    cornerRadius: barWidth / 2
                                ),
                                rect: rect,
                                opacity: 0.18 + Double(value) * 0.82
                            )
                        }

                        context.drawLayer { glow in
                            glow.addFilter(.blur(radius: 6))

                            for bar in bars {
                                glow.fill(
                                    bar.path,
                                    with: .color(
                                        accent.opacity(bar.opacity * 0.30)
                                    )
                                )
                            }
                        }

                        for bar in bars {
                            context.fill(
                                bar.path,
                                with: .linearGradient(
                                    Gradient(colors: [
                                        accent.opacity(bar.opacity * 0.42),
                                        accent.opacity(bar.opacity),
                                        .white.opacity(bar.opacity * 0.42)
                                    ]),
                                    startPoint: CGPoint(
                                        x: bar.rect.midX,
                                        y: bar.rect.maxY
                                    ),
                                    endPoint: CGPoint(
                                        x: bar.rect.midX,
                                        y: bar.rect.minY
                                    )
                                )
                            )
                        }
                    }
                }
            }
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.12),
                    .init(color: .white.opacity(0.62), location: 0.48),
                    .init(color: .white, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func level(
        at index: Int,
        count: Int,
        time: TimeInterval,
        usesLiveLevels: Bool
    ) -> CGFloat {
        let position = CGFloat(index) / CGFloat(max(count - 1, 1))

        guard usesLiveLevels, !levels.isEmpty else {
            let phase = Double(position)
            let wave = sin(phase * .pi * 5.2 + time * 2.15)
                + sin(phase * .pi * 11.3 - time * 1.37) * 0.34
            let pulse = 0.56 + sin(time * 1.25 + phase * 2.4) * 0.22
            let envelope = sin(phase * .pi)
            return min(max(CGFloat((pulse + wave * 0.16) * envelope), 0), 1)
        }

        let mapped = CGFloat(index) / CGFloat(max(count - 1, 1))
            * CGFloat(max(levels.count - 1, 0))
        let lower = Int(floor(mapped))
        let upper = min(lower + 1, levels.count - 1)
        let fraction = mapped - CGFloat(lower)
        let value = levels[lower] * (1 - fraction)
            + levels[upper] * fraction
        return min(max(value, 0), 1)
    }
}

private struct PixelMatrixBackground: View {
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let musicNoteGlyph = [
        "......####",
        "......####",
        "......####",
        "......###.",
        "......###.",
        "......###.",
        "###...###.",
        "#####.###.",
        "#####.###.",
        "#####.###.",
        ".#######..",
        "..#####..."
    ]

    private static let sparkleGlyph = [
        "...#...",
        "...#...",
        ".#####.",
        "#######",
        ".#####.",
        "...#...",
        "...#..."
    ]

    private static let smallSparkleGlyph = [
        ".#.",
        "###",
        ".#."
    ]

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: reduceMotion
            )
        ) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                drawMatrix(in: &context, size: size, time: time)
            }
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.28),
                    .init(color: .white.opacity(0.38), location: 0.50),
                    .init(color: .white, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawMatrix(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        guard size.width > 0, size.height > 0 else { return }

        let bounds = CGRect(origin: .zero, size: size)
        context.fill(
            Path(bounds),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: accent.opacity(0.82), location: 0),
                    .init(color: accent.opacity(0.68), location: 0.52),
                    .init(color: accent.opacity(0.42), location: 1)
                ]),
                startPoint: CGPoint(x: 0, y: size.height),
                endPoint: CGPoint(x: size.width, y: 0)
            )
        )
        context.fill(
            Path(bounds),
            with: .radialGradient(
                Gradient(colors: [
                    accent.opacity(0.18),
                    .clear
                ]),
                center: CGPoint(x: size.width * 0.46, y: size.height * 0.72),
                startRadius: 0,
                endRadius: size.width * 0.62
            )
        )
        context.fill(
            Path(bounds),
            with: .radialGradient(
                Gradient(colors: [
                    .clear,
                    .black.opacity(0.24)
                ]),
                center: CGPoint(x: size.width * 0.50, y: size.height * 0.62),
                startRadius: min(size.width, size.height) * 0.18,
                endRadius: max(size.width, size.height) * 0.72
            )
        )

        context.blendMode = .screen
        drawDotGrid(in: &context, size: size, time: time)
        drawGlyphCluster(in: &context, size: size, time: time)
    }

    private func drawDotGrid(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        let spacing = max(7.5, min(10.5, size.height * 0.052))
        let dotSize = max(1.1, spacing * 0.15)
        let columnCount = Int(size.width / spacing) + 1
        let rowCount = Int(size.height / spacing) + 1
        let scanX = CGFloat(fraction(time * 0.055)) * size.width
        let focus = CGPoint(x: size.width * 0.50, y: size.height * 0.70)

        for row in 0...rowCount {
            for column in 0...columnCount {
                let x = (CGFloat(column) + 0.5) * spacing
                let y = (CGFloat(row) + 0.5) * spacing
                let shimmer = 0.5 + 0.5 * sin(
                    time * 1.15
                        + Double(row) * 0.73
                        + Double(column) * 0.41
                )
                let scanDistance = abs(x - scanX) / max(size.width * 0.14, 1)
                let scanGlow = max(0, 1 - scanDistance) * 0.12
                let dx = Double(x - focus.x)
                let dy = Double(y - focus.y)
                let focusDistance = sqrt(dx * dx + dy * dy)
                let focusGlow = max(
                    0,
                    1 - focusDistance / Double(size.width * 0.58)
                ) * 0.07
                let opacity = 0.10 + shimmer * 0.08 + scanGlow + focusGlow
                let offsetX = CGFloat(
                    sin(time * 0.55 + Double(row) * 0.57)
                ) * 0.22
                let offsetY = CGFloat(
                    cos(time * 0.48 + Double(column) * 0.49)
                ) * 0.22
                let dot = CGRect(
                    x: x + offsetX - dotSize / 2,
                    y: y + offsetY - dotSize / 2,
                    width: dotSize,
                    height: dotSize
                )

                context.fill(
                    Path(dot),
                    with: .color(.white.opacity(opacity))
                )
            }
        }
    }

    private func drawGlyphCluster(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        let motifs: [(rows: [String], column: Int, row: Int)] = [
            (Self.musicNoteGlyph, 0, 3),
            (Self.smallSparkleGlyph, 13, 0),
            (Self.musicNoteGlyph, 18, 5),
            (Self.sparkleGlyph, 31, 1),
            (Self.musicNoteGlyph, 39, 2),
            (Self.smallSparkleGlyph, 53, 7)
        ]
        let cellSize = max(4.1, min(4.9, size.height * 0.037))
        let step = cellSize * 1.16
        let groupWidth = 58 * step
        let groupHeight = 17 * step
        let travelDistance = size.width + groupWidth
        let baseTravelProgress = fraction(time * 0.045)
        let driftY = CGFloat(cos(time * 0.27)) * 1.0
        var glyphPath = Path()
        var cells: [(rect: CGRect, opacity: Double)] = []

        for phase in [0.0, 0.5] {
            let travelProgress = fraction(baseTravelProgress + phase)
            let origin = CGPoint(
                x: -groupWidth + CGFloat(travelProgress) * travelDistance,
                y: size.height * 0.70 - groupHeight / 2 + driftY
            )

            for motif in motifs {
                let swayPhase = time * 1.25
                    + Double(motif.column) * 0.29
                let swayX = CGFloat(sin(swayPhase)) * 1.8
                let bobY = CGFloat(
                    cos(swayPhase * 0.78 + 0.9)
                ) * 3.0

                for (rowIndex, row) in motif.rows.enumerated() {
                    for (columnIndex, character) in row.enumerated()
                    where character == "#" {
                        let rect = CGRect(
                            x: origin.x + swayX
                                + CGFloat(motif.column + columnIndex) * step,
                            y: origin.y + bobY
                                + CGFloat(motif.row + rowIndex) * step,
                            width: cellSize,
                            height: cellSize
                        )
                        let shimmer = 0.5 + 0.5 * sin(
                            time * 1.45
                                + Double(columnIndex) * 0.42
                                + Double(rowIndex) * 0.55
                        )

                        glyphPath.addRect(rect)
                        cells.append((rect, 0.82 + shimmer * 0.16))
                    }
                }
            }
        }

        let groupPulse = 0.88 + 0.12 * sin(time * 1.35)

        context.drawLayer { glowLayer in
            glowLayer.blendMode = .screen
            glowLayer.addFilter(.blur(radius: 5.8))
            glowLayer.fill(
                glyphPath,
                with: .color(.white.opacity(0.34 * groupPulse))
            )
        }

        context.drawLayer { sharpLayer in
            sharpLayer.blendMode = .screen
            sharpLayer.addFilter(.blur(radius: 0.22))

            for cell in cells {
                sharpLayer.fill(
                    Path(cell.rect),
                    with: .color(.white.opacity(cell.opacity)))
            }
        }
    }

    private func fraction(_ value: Double) -> Double {
        value - floor(value)
    }
}

private struct GradientWavesBackground: View {
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: reduceMotion
            )
        ) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                drawWaves(in: &context, size: size, time: time)
            }
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.22),
                    .init(color: .white.opacity(0.38), location: 0.46),
                    .init(color: .white, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawWaves(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        guard size.width > 0, size.height > 0 else { return }

        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(colors: [
                    accent.opacity(0.20),
                    accent.opacity(0.055),
                    .clear
                ]),
                center: CGPoint(x: size.width * 0.52, y: size.height * 0.74),
                startRadius: 0,
                endRadius: size.width * 0.58
            )
        )

        for layer in (0..<5).reversed() {
            let depth = Double(layer) / 4
            let baseY = size.height * CGFloat(0.43 + depth * 0.13)
            let amplitude = size.height * CGFloat(0.10 + depth * 0.045)
            let frequency = 0.92 + depth * 0.34
            let phase = depth * 2.1
            var fill = Path()
            var crest = Path()
            var isFirstPoint = true

            fill.move(to: CGPoint(x: -14, y: size.height + 14))

            for x in stride(
                from: CGFloat(-14),
                through: size.width + 14,
                by: 2
            ) {
                let progress = Double(x / size.width)
                let wave = sin(
                    progress * .pi * 2 * frequency
                        + time * (0.16 + depth * 0.035)
                        + phase
                )
                    + sin(
                        progress * .pi * 4.4
                            - time * (0.11 + depth * 0.022)
                            + phase * 1.7
                    ) * 0.34
                    + sin(
                        progress * .pi * 8.6
                            + time * 0.08
                            + Double(layer) * 0.9
                    ) * 0.12
                let y = baseY - CGFloat(wave) * amplitude
                let point = CGPoint(x: x, y: y)

                if isFirstPoint {
                    crest.move(to: point)
                    isFirstPoint = false
                } else {
                    crest.addLine(to: point)
                }
                fill.addLine(to: point)
            }

            fill.addLine(
                to: CGPoint(x: size.width + 14, y: size.height + 14)
            )
            fill.closeSubpath()

            let gradient = Gradient(stops: [
                .init(color: accent.opacity(0.04), location: 0),
                .init(
                    color: accent.opacity(0.10 + (1 - depth) * 0.08),
                    location: 0.34
                ),
                .init(color: accent.opacity(0.055), location: 0.70),
                .init(color: .black.opacity(0.22), location: 1)
            ])

            context.drawLayer { waveLayer in
                waveLayer.addFilter(.blur(radius: 1.1 + depth * 2.1))
                waveLayer.fill(
                    fill,
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(
                            x: 0,
                            y: baseY - amplitude * 1.5
                        ),
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )
            }

            context.drawLayer { glowLayer in
                glowLayer.blendMode = .screen
                glowLayer.addFilter(.blur(radius: 4.2 + depth * 1.8))
                glowLayer.stroke(
                    crest,
                    with: .color(accent.opacity(0.22 - depth * 0.045)),
                    style: StrokeStyle(
                        lineWidth: 3.2 + CGFloat(depth) * 1.8,
                        lineCap: .round
                    )
                )
            }

            context.drawLayer { highlightLayer in
                highlightLayer.blendMode = .screen
                highlightLayer.addFilter(.blur(radius: 0.45 + depth * 1.1))
                highlightLayer.stroke(
                    crest,
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: accent.opacity(0.18), location: 0),
                            .init(
                                color: accent.opacity(0.76 - depth * 0.20),
                                location: 0.42
                            ),
                            .init(
                                color: .white.opacity(0.50 - depth * 0.12),
                                location: 0.58
                            ),
                            .init(color: accent.opacity(0.16), location: 1)
                        ]),
                        startPoint: CGPoint(x: 0, y: baseY),
                        endPoint: CGPoint(x: size.width, y: baseY)
                    ),
                    style: StrokeStyle(
                        lineWidth: 0.82 + CGFloat(depth) * 0.92,
                        lineCap: .round
                    )
                )
            }
        }
    }
}

private struct AeroShardsBackground: View {
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: reduceMotion
            )
        ) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                drawShards(in: &context, size: size, time: time)
            }
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.28),
                    .init(color: .white.opacity(0.38), location: 0.50),
                    .init(color: .white, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawShards(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        guard size.width > 0, size.height > 0 else { return }

        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(colors: [
                    accent.opacity(0.12),
                    accent.opacity(0.035),
                    .clear
                ]),
                center: CGPoint(x: size.width * 0.54, y: size.height * 0.68),
                startRadius: 0,
                endRadius: size.width * 0.54
            )
        )

        for layer in (0..<5).reversed() {
            let depth = Double(layer) / 4
            let baseY = size.height * CGFloat(0.51 + depth * 0.085)
            let bandHeight = size.height * CGFloat(0.075 + depth * 0.035)
            let shardCount = 50 - layer * 4

            for strand in 0..<2 {
                context.drawLayer { glowLayer in
                    glowLayer.blendMode = .screen
                    glowLayer.addFilter(.blur(radius: 4.2 + depth * 2.4))

                    for index in 0..<shardCount {
                        let shard = shardGeometry(
                            layer: layer,
                            strand: strand,
                            index: index,
                            count: shardCount,
                            size: size,
                            baseY: baseY,
                            bandHeight: bandHeight,
                            time: time
                        )
                        glowLayer.fill(
                            shard.path,
                            with: .color(accent.opacity(0.085))
                        )
                    }
                }

                context.drawLayer { sharpLayer in
                    sharpLayer.blendMode = .screen
                    sharpLayer.addFilter(.blur(radius: 0.22 + depth * 0.62))

                    for index in 0..<shardCount {
                        let shard = shardGeometry(
                            layer: layer,
                            strand: strand,
                            index: index,
                            count: shardCount,
                            size: size,
                            baseY: baseY,
                            bandHeight: bandHeight,
                            time: time
                        )
                        let opacity = 0.16 + shard.shine * 0.40
                        sharpLayer.fill(
                            shard.path,
                            with: .color(accent.opacity(opacity))
                        )
                        sharpLayer.stroke(
                            shard.path,
                            with: .color(
                                Color.white.opacity(0.14 + shard.shine * 0.44)
                            ),
                            lineWidth: 0.36 + shard.shine * 0.50
                        )
                    }
                }
            }
        }

        drawMarkers(in: &context, size: size, time: time)
    }

    private func shardGeometry(
        layer: Int,
        strand: Int,
        index: Int,
        count: Int,
        size: CGSize,
        baseY: CGFloat,
        bandHeight: CGFloat,
        time: TimeInterval
    ) -> (path: Path, shine: CGFloat) {
        let depth = Double(layer) / 4
        let seedA = randomSeed(layer: layer, index: index)
        let seedB = randomSeed(layer: layer, index: index + 101)
        let seedC = randomSeed(layer: layer, index: index + 211)
        let speed = 0.010 + (1 - depth) * 0.006
        let progress = fraction(
            Double(index) / Double(count)
                + time * speed
                + Double(strand) * 0.37
                + Double(layer) * 0.11
                + (seedA - 0.5) * 0.015
        )
        let x = CGFloat(progress) * (size.width + 72) - 36
        let phase = time * (0.32 + depth * 0.08)
            + Double(index) * 0.77
            + Double(layer) * 1.13
            + Double(strand) * 2.37
        let slope = (strand == 0 ? -0.22 : 0.22)
            + (strand == 0 ? depth * 0.04 : -depth * 0.04)
        let y = baseY
            + CGFloat(slope) * (x - size.width / 2)
            + CGFloat(sin(progress * .pi * 2.4 + phase))
                * bandHeight * 0.45
            + CGFloat(seedB - 0.5) * bandHeight * 0.70
        let rotation = CGFloat(atan(slope))
            + CGFloat(sin(phase * 0.83)) * 0.20
            + CGFloat(seedC - 0.5) * 0.55
        let length = CGFloat(5 + seedB * 11)
            * CGFloat(1.22 - depth * 0.34)
        let thickness = CGFloat(0.68 + seedC * 1.72)
            * CGFloat(1.10 - depth * 0.20)
        let skew = CGFloat((seedA - 0.5) * 0.85)
        let shine = CGFloat(
            0.45 + 0.55 * (0.5 + 0.5 * sin(phase * 1.7 + seedC * 4))
        )

        return (
            shardPath(
                center: CGPoint(x: x, y: y),
                length: length,
                thickness: thickness,
                rotation: rotation,
                skew: skew
            ),
            shine
        )
    }

    private func shardPath(
        center: CGPoint,
        length: CGFloat,
        thickness: CGFloat,
        rotation: CGFloat,
        skew: CGFloat
    ) -> Path {
        let cosine = CGFloat(cos(Double(rotation)))
        let sine = CGFloat(sin(Double(rotation)))

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let skewedX = x + y * skew
            return CGPoint(
                x: center.x + skewedX * cosine - y * sine,
                y: center.y + skewedX * sine + y * cosine
            )
        }

        var path = Path()
        path.move(to: point(-length / 2, -thickness / 2))
        path.addLine(to: point(length / 2, -thickness / 2))
        path.addLine(to: point(length / 2, thickness / 2))
        path.addLine(to: point(-length / 2, thickness / 2))
        path.closeSubpath()
        return path
    }

    private func drawMarkers(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        for index in 0..<9 {
            let seed = Double(index) * 0.173 + 0.08
            let x = CGFloat(fraction(seed + sin(time * 0.04 + Double(index)) * 0.015))
                * size.width
            let yProgress = fraction(Double(index) * 0.317 + 0.22)
            let y = size.height * CGFloat(0.38 + yProgress * 0.52)
            let length = CGFloat(1.6 + Double(index % 3) * 0.7)
            let opacity = 0.16 + Double(index % 4) * 0.04
            var marker = Path()
            marker.move(to: CGPoint(x: x - length, y: y))
            marker.addLine(to: CGPoint(x: x + length, y: y))
            marker.move(to: CGPoint(x: x, y: y - length))
            marker.addLine(to: CGPoint(x: x, y: y + length))
            context.stroke(
                marker,
                with: .color(accent.opacity(opacity)),
                lineWidth: 0.55
            )
        }
    }

    private func randomSeed(layer: Int, index: Int) -> Double {
        let seed = Double(layer * 997 + index * 37)
        let value = sin(seed * 12.9898 + 78.233) * 43758.5453
        return value - floor(value)
    }

    private func fraction(_ value: Double) -> Double {
        value - floor(value)
    }
}

private struct AuroraGlow: View {
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: reduceMotion
            )
        ) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                context.blendMode = .screen
                context.addFilter(
                    .blur(radius: max(5, size.height * 0.055))
                )

                for layer in 0..<3 {
                    drawAuroraLayer(
                        in: &context,
                        size: size,
                        time: time,
                        layer: layer
                    )
                }
            }
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.34),
                    .init(color: .white.opacity(0.45), location: 0.56),
                    .init(color: .white, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawAuroraLayer(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval,
        layer: Int
    ) {
        guard size.width > 0, size.height > 0 else { return }

        let width = size.width
        let height = size.height
        let layerValue = Double(layer)
        let phase = layerValue * 1.65
        let baseY = height * (0.66 + CGFloat(layer) * 0.045)
        let amplitude = height * (0.135 + CGFloat(layer) * 0.018)
        var edgePath = Path()

        for x in stride(from: CGFloat(-4), through: width + 4, by: 4) {
            let progress = Double(x / width)
            let wave = sin(progress * .pi * 2.1 + time * 0.95 + phase)
                + sin(progress * .pi * 5.2 - time * 0.62 + phase * 0.7) * 0.46
                + sin(progress * .pi * 9.4 + time * 0.38 - phase * 0.35) * 0.18
            let y = baseY + CGFloat(wave) * amplitude
            let point = CGPoint(x: x, y: y)

            if x == -4 {
                edgePath.move(to: point)
            } else {
                edgePath.addLine(to: point)
            }
        }

        var fillPath = edgePath
        fillPath.addLine(to: CGPoint(x: width + 4, y: height + 4))
        fillPath.addLine(to: CGPoint(x: -4, y: height + 4))
        fillPath.closeSubpath()

        let intensity = 0.78 - layerValue * 0.16
        let gradient = Gradient(stops: [
            .init(color: accent.opacity(0.10 * intensity), location: 0),
            .init(color: accent.opacity(0.92 * intensity), location: 0.48),
            .init(color: accent.opacity(0.14 * intensity), location: 1)
        ])
        context.fill(
            fillPath,
            with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: 0, y: height),
                endPoint: CGPoint(x: width, y: height)
            )
        )

        context.stroke(
            edgePath,
            with: .color(accent.opacity(0.34 * intensity)),
            style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
        )
    }
}

private struct ProceduralNotchBackground: View {
    let effect: NotchBackgroundEffect
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct GalaxyStar {
        let center: CGPoint
        let radius: CGFloat
        let opacity: Double
        let path: Path
    }

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: reduceMotion
            )
        ) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                guard size.width > 0, size.height > 0 else { return }
                context.blendMode = .screen

                switch effect {
                case .aurora:
                    break
                case .threads:
                    drawThreads(in: &context, size: size, time: time)
                case .hyperspeed:
                    drawHyperspeed(in: &context, size: size, time: time)
                case .galaxy:
                    drawGalaxy(in: &context, size: size, time: time)
                case .gradientWaves, .aeroShards, .pixelMatrix, .spectrum:
                    break
                }
            }
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.30),
                    .init(color: .white.opacity(0.34), location: 0.52),
                    .init(color: .white, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawThreads(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        let width = size.width
        let height = size.height

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 0.85))

            for index in 0..<22 {
                let depth = CGFloat(index) / 21
                let baseY = height * (0.39 + depth * 0.63)
                let amplitude = height * (0.045 + depth * 0.055)
                let phase = Double(index) * 0.53
                var path = Path()

                for x in stride(from: CGFloat(-4), through: width + 4, by: 4) {
                    let progress = Double(x / width)
                    let wave = sin(progress * .pi * 3.2 + time * 0.72 + phase)
                        + sin(progress * .pi * 7.4 - time * 0.43 + phase * 0.6) * 0.34
                    let y = baseY + CGFloat(wave) * amplitude
                    let point = CGPoint(x: x, y: y)

                    if x == -4 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }

                let intensity = 0.90 - Double(depth) * 0.35
                layer.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: accent.opacity(0.09), location: 0),
                            .init(color: accent.opacity(intensity), location: 0.46),
                            .init(color: accent.opacity(0.10), location: 1)
                        ]),
                        startPoint: CGPoint(x: 0, y: baseY),
                        endPoint: CGPoint(x: width, y: baseY)
                    ),
                    style: StrokeStyle(
                        lineWidth: 0.85 + depth * 1.25,
                        lineCap: .round
                    )
                )
            }
        }

        for index in 0..<10 {
            let seed = Double(index)
            let progress = fraction(time * 0.055 + seed * 0.173)
            let x = CGFloat(progress) * width
            let wave = sin(progress * .pi * 3.2 + time * 0.72 + seed * 0.53)
            let y = height * 0.72 + CGFloat(wave) * height * 0.17
            let note = index.isMultiple(of: 3) ? "♫" : "♪"
            let fontSize = 11 + CGFloat(index % 3) * 1.8
            let resolvedNote = context.resolve(
                Text(note)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(accent.opacity(0.90))
            )
            context.draw(resolvedNote, at: CGPoint(x: x, y: y), anchor: .center)
        }
    }

    private func drawHyperspeed(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        let width = size.width
        let height = size.height
        let focus = CGPoint(x: width * 0.5, y: height * 0.54)
        let colors: [Color] = [
            Color(red: 1.00, green: 0.24, blue: 0.32),
            Color(red: 1.00, green: 0.48, blue: 0.12),
            Color(red: 1.00, green: 0.84, blue: 0.18),
            Color(red: 0.32, green: 0.92, blue: 0.48),
            Color(red: 0.16, green: 0.82, blue: 1.00),
            Color(red: 0.34, green: 0.48, blue: 1.00),
            Color(red: 0.72, green: 0.34, blue: 1.00),
            Color(red: 1.00, green: 0.28, blue: 0.72)
        ]

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 0.6))

            for index in 0..<38 {
                let ratio = Double(index) / 37
                let angle = (ratio - 0.5) * 2.28
                let cycle = fraction(
                    time * (0.18 + Double(index % 5) * 0.018)
                        + Double(index) * 0.137
                )
                let near = 0.035 + cycle * 0.48
                let far = min(1.24, near + 0.10 + cycle * 0.18)
                let nearPoint = CGPoint(
                    x: focus.x + CGFloat(sin(angle)) * width * 0.92 * near,
                    y: focus.y + CGFloat(cos(angle)) * height * 0.86 * near
                )
                let farPoint = CGPoint(
                    x: focus.x + CGFloat(sin(angle)) * width * 0.92 * far,
                    y: focus.y + CGFloat(cos(angle)) * height * 0.86 * far
                )
                let startColor = colors[index % colors.count]
                let endColor = colors[(index * 3 + 2) % colors.count]
                var streak = Path()
                streak.move(to: nearPoint)
                streak.addLine(to: farPoint)
                layer.stroke(
                    streak,
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: startColor.opacity(0.08), location: 0),
                            .init(color: startColor.opacity(0.92), location: 0.62),
                            .init(color: endColor.opacity(0.86), location: 0.88),
                            .init(color: endColor.opacity(0.08), location: 1)
                        ]),
                        startPoint: nearPoint,
                        endPoint: farPoint
                    ),
                    style: StrokeStyle(
                        lineWidth: 0.55 + CGFloat(cycle) * 1.4,
                        lineCap: .round
                    )
                )
            }
        }
    }

    private func drawGalaxy(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        let width = size.width
        let height = size.height
        let stars = (0..<104).map { index -> GalaxyStar in
            let seed = Double(index)
            let fallSpeed = 0.014 + Double(index % 7) * 0.0028
            let sway = sin(time * 0.42 + seed * 1.71) * 0.018
            let xProgress = fraction(
                seed * 0.754877666 + 0.09 + sway
            )
            let yProgress = fraction(
                seed * 0.4637211 + time * fallSpeed
            )
            let center = CGPoint(
                x: CGFloat(xProgress) * width,
                y: height * (0.10 + CGFloat(yProgress) * 1.0)
            )
            let sizeSeed = fraction(seed * 3.173 + 0.37)
            let radius = CGFloat(0.85 + pow(sizeSeed, 1.8) * 4.6)
            let twinkle = 0.42 + pow(
                max(0, sin(time * 0.9 + seed * 1.37)),
                2
            ) * 0.58
            let variant = Int(fraction(seed * 6.917 + 2.13) * 10)
            let rotation = fraction(seed * 4.731 + 0.29) * .pi * 2
                + time * (0.035 + Double(index % 4) * 0.012)
            let horizontalScale = 0.62
                + CGFloat(fraction(seed * 2.417 + 4.81)) * 0.92
            let verticalScale = 0.62
                + CGFloat(fraction(seed * 5.123 + 1.67)) * 0.92
            let pinch = 0.08
                + CGFloat(fraction(seed * 8.219 + 3.41)) * 0.18
            let path: Path

            if variant == 9 || radius < 1.1 {
                let dotRadius = max(radius * 0.58, 0.65)
                path = Path(
                    ellipseIn: CGRect(
                        x: center.x - dotRadius,
                        y: center.y - dotRadius,
                        width: dotRadius * 2,
                        height: dotRadius * 2
                    )
                )
            } else {
                path = fourPointStarPath(
                    center: center,
                    horizontalRadius: radius * horizontalScale,
                    verticalRadius: radius * verticalScale,
                    pinch: pinch,
                    rotation: rotation
                )
            }

            return GalaxyStar(
                center: center,
                radius: radius,
                opacity: twinkle,
                path: path
            )
        }

        context.drawLayer { glowLayer in
            glowLayer.addFilter(.blur(radius: 4.2))

            for star in stars where star.radius > 1.5 {
                let glowRect = CGRect(
                    x: star.center.x - star.radius * 2.8,
                    y: star.center.y - star.radius * 2.8,
                    width: star.radius * 5.6,
                    height: star.radius * 5.6
                )
                glowLayer.fill(
                    Path(ellipseIn: glowRect),
                    with: .radialGradient(
                        Gradient(colors: [
                            .white.opacity(star.opacity * 0.34),
                            .white.opacity(star.opacity * 0.12),
                            .clear
                        ]),
                        center: star.center,
                        startRadius: 0,
                        endRadius: star.radius * 2.8
                    )
                )
                glowLayer.fill(
                    star.path,
                    with: .color(.white.opacity(star.opacity * 0.54))
                )
            }
        }

        context.drawLayer { sharpLayer in
            sharpLayer.addFilter(.blur(radius: 0.16))

            for star in stars {
                sharpLayer.fill(
                    star.path,
                    with: .color(.white.opacity(star.opacity))
                )
            }
        }
    }

    private func fourPointStarPath(
        center: CGPoint,
        horizontalRadius: CGFloat,
        verticalRadius: CGFloat,
        pinch: CGFloat,
        rotation: Double
    ) -> Path {
        let cosine = CGFloat(cos(rotation))
        let sine = CGFloat(sin(rotation))

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: center.x + x * cosine - y * sine,
                y: center.y + x * sine + y * cosine
            )
        }

        var path = Path()
        path.move(to: point(0, -verticalRadius))
        path.addQuadCurve(
            to: point(horizontalRadius, 0),
            control: point(
                horizontalRadius * pinch,
                -verticalRadius * pinch
            )
        )
        path.addQuadCurve(
            to: point(0, verticalRadius),
            control: point(
                horizontalRadius * pinch,
                verticalRadius * pinch
            )
        )
        path.addQuadCurve(
            to: point(-horizontalRadius, 0),
            control: point(
                -horizontalRadius * pinch,
                verticalRadius * pinch
            )
        )
        path.addQuadCurve(
            to: point(0, -verticalRadius),
            control: point(
                -horizontalRadius * pinch,
                -verticalRadius * pinch
            )
        )
        path.closeSubpath()

        return path
    }

    private func fraction(_ value: Double) -> Double {
        value - floor(value)
    }
}

private struct NotchBlurTransitionModifier: ViewModifier, Animatable {
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}

private struct NotchShape: Shape {
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

private struct CompactSystemActivity: Identifiable {
    let id: String
    let icon: String
    let name: String?
    let tint: Color
    let accessibilityLabel: String
}

private struct AirPodsStatusIcon: View {
    let model: AirPodsModelKind
    let size: CGFloat

    var body: some View {
        AirPods3DView(model: model)
            .id(model)
            .frame(width: size, height: size)
            .accessibilityLabel("\(model.displayName) 已连接")
    }
}

private struct CompactVolumeRing: View {
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

private struct CompactPlaybackIndicator: View {
    let color: Color
    let levels: [CGFloat]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate

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
                            height: barHeight(at: time, index: index)
                        )
                }
            }
            .frame(width: 15, height: 14)
            .shadow(color: color.opacity(0.3), radius: 1.5)
        }
        .accessibilityLabel("正在播放")
    }

    private func barHeight(at time: TimeInterval, index: Int) -> CGFloat {
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

private struct PlaybackButton: View {
    let systemName: String
    let label: String
    let tint: Color
    var activeTint: Color?
    var emphasized = false
    var isActive = false
    var fontSize: CGFloat?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(
                    .system(
                        size: fontSize ?? (emphasized ? 12 : 11),
                        weight: .bold
                    )
                )
                .foregroundStyle(
                    isActive
                        ? activeTint ?? tint
                        : isHovering
                            ? tint
                        : Color.white.opacity(emphasized ? 1 : 0.76)
                )
                .frame(width: 28, height: 28)
                .contentShape(Circle())
                .animation(
                    .easeOut(duration: 0.14),
                    value: isHovering
                )
                .animation(
                    .easeOut(duration: 0.16),
                    value: isActive
                )
                .onHover { hovering in
                    isHovering = hovering
                }
        }
        .buttonStyle(PlaybackPressStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct PlaybackPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(
                .easeOut(duration: 0.08),
                value: configuration.isPressed
            )
    }
}

private struct NotchActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Color.white.opacity(configuration.isPressed ? 0.22 : 0.13),
                in: Capsule()
            )
    }
}

private struct HoverParallaxModifier: ViewModifier {
    let size: CGFloat
    var isEnabled = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation = CGSize.zero
    @State private var isHovering = false

    private let maxTilt: CGFloat = 6

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(Double(rotation.height)),
                axis: (x: 1, y: 0, z: 0),
                perspective: 0.55
            )
            .rotation3DEffect(
                .degrees(Double(rotation.width)),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.55
            )
            .scaleEffect(isHovering && !reduceMotion ? 1.015 : 1)
            .animation(
                .spring(response: 0.26, dampingFraction: 0.82),
                value: rotation
            )
            .animation(
                .spring(response: 0.28, dampingFraction: 0.86),
                value: isHovering
            )
            .onContinuousHover { phase in
                guard isEnabled, !reduceMotion else {
                    reset()
                    return
                }

                switch phase {
                case .active(let location):
                    isHovering = true
                    updateRotation(at: location)
                case .ended:
                    reset()
                }
            }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled {
                    reset()
                }
            }
            .onChange(of: reduceMotion) { _, reduced in
                if reduced {
                    reset()
                }
            }
    }

    private func updateRotation(at location: CGPoint) {
        let x = min(max(location.x / size, 0), 1) - 0.5
        let y = min(max(location.y / size, 0), 1) - 0.5
        rotation = CGSize(
            width: x * maxTilt * 2,
            height: -y * maxTilt * 2
        )
    }

    private func reset() {
        rotation = .zero
        isHovering = false
    }
}

private extension View {
    func hoverParallax(size: CGFloat, isEnabled: Bool = true) -> some View {
        modifier(HoverParallaxModifier(size: size, isEnabled: isEnabled))
    }
}
