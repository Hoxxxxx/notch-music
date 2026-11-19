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
        .previous,
        .playPause,
        .next,
        .shuffle,
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
    case galaxy
    case gradientWaves
    case aeroShards
    case pixelMatrix
    case spectrum
    case albumFlow

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .aurora:
            return "极光"
        case .threads:
            return "丝线"
        case .galaxy:
            return "星系"
        case .gradientWaves:
            return "渐变波浪"
        case .aeroShards:
            return "碎片"
        case .pixelMatrix:
            return "像素矩阵"
        case .spectrum:
            return "声谱"
        case .albumFlow:
            return "专辑墙"
        }
    }

    var systemImage: String {
        switch self {
        case .aurora:
            return "water.waves"
        case .threads:
            return "music.note.list"
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
        case .albumFlow:
            return "rectangle.stack.fill"
        }
    }
}

enum NotchBackgroundSettings {
    static let enabled = "NotchMusic.notchBackground.enabled"
    static let effect = "NotchMusic.notchBackground.effect"
    static let alwaysVisible = "NotchMusic.notchBackground.alwaysVisible"
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

enum ContentPageTransitionDirection {
    case forward
    case backward
}

enum EffectMath {
    static func fraction(_ value: Double) -> Double {
        value - floor(value)
    }

    static func hash(_ value: Int) -> Double {
        let raw = sin(Double(value) * 12.9898 + 78.233) * 43758.5453
        return fraction(raw)
    }

    static func randomSeed(layer: Int, index: Int) -> Double {
        hash(layer * 997 + index * 37)
    }
}

private enum PixelTypography {
    static func font(size: CGFloat) -> Font {
        .system(size: size)
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
    private var progressTrackStyleRaw = ProgressTrackStyle.softAurora.rawValue
    @AppStorage(NotchBackgroundSettings.enabled)
    private var notchBackgroundEnabled = true
    @AppStorage(NotchBackgroundSettings.effect)
    private var notchBackgroundEffectRaw = NotchBackgroundEffect.aurora.rawValue
    @AppStorage(NotchBackgroundSettings.alwaysVisible)
    private var notchBackgroundAlwaysVisible = false
    @AppStorage(SystemHUDSettings.style)
    private var systemHUDStyleRaw = SystemHUDStyle.customOSD.rawValue
    @AppStorage(SoundHUDSettings.content)
    private var soundHUDContentRaw = SoundHUDContent.device.rawValue
    @AppStorage(WatchFaceStyle.storageKey)
    private var watchFaceStyleRaw = WatchFaceStyle.classic.rawValue
    @AppStorage(WatchFaceDisplaySettings.showsInMusicKey)
    private var showsWatchFaceInMusic = true
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
    @AppStorage(NotchLayout.notchWidthAdjustment)
    private var notchWidthAdjustment = 0
    @AppStorage(NotchLayout.notchHeightAdjustment)
    private var notchHeightAdjustment = 0
    @AppStorage(NotchLayout.notchPreviewWidth)
    private var notchPreviewWidth = 0
    @AppStorage(NotchLayout.notchPreviewHeight)
    private var notchPreviewHeight = 0
    @AppStorage(NotchLayout.notchPreviewActive)
    private var isNotchPreviewActive = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var suppressedCompactPresentations:
        Set<CompactPresentation> = []
    @State private var keepsPausedCompactPresentation = false
    @State private var playbackLingerTask: Task<Void, Never>?

    private let expandedArtworkSize: CGFloat = 96
    private let compactExpandedArtworkSize: CGFloat = 118
    private let compactExpandedRowHeight: CGFloat = 22
    private let volumeSliderPillWidth: CGFloat = 108
    private let expandedWatchFaceSize = NotchLayout.expandedContentHeight
    private let compactOuterPadding: CGFloat = 6

    private enum CompactPresentation: Hashable {
        case lock
        case unlock
        case device
        case activity(String)
        case playback
    }

    private struct EmptyStatePresentation {
        let title: String
        let description: String
        let icon: String
        let actionTitle: String
        let action: () -> Void
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
        ProgressTrackStyle(rawValue: progressTrackStyleRaw) ?? .softAurora
    }

    private var soundHUDContent: SoundHUDContent {
        SoundHUDContent(rawValue: soundHUDContentRaw) ?? .device
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
        let showsArtwork =
            usesExpandedLayout || compactPresentation == .playback
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
        let hudHeight: CGFloat = 96
        let hudTopCornerRadius = NotchLayout.expandedTopCornerRadius
        let hudWidth =
            panelState.notchWidth + 28 + hudTopCornerRadius * 2
        let topCornerRadius: CGFloat = showsExpandedHUD
            ? hudTopCornerRadius
            : usesExpandedLayout
            ? NotchLayout.expandedTopCornerRadius
            : 10
        let bottomCornerRadius: CGFloat = showsExpandedHUD
            ? 22
            : usesExpandedLayout
            ? 24
            : showsNotchSideHUD ? 20 : showsScreenStateIconOnly ? 12 : 14
        let compactWidth =
            NotchLayout.compactWidth(
                notchWidth: panelState.notchWidth,
                wingWidth: compactWingWidth
            ) + topCornerRadius * 2 + hoverPreviewWidth
        let size = CGSize(
            width: showsNotchSideHUD
                ? NotchLayout.sideHUDWidth(notchWidth: panelState.notchWidth)
                : showsExpandedHUD
                ? hudWidth
                : usesExpandedLayout
                ? expandedPanelWidth
                : compactWidth,
            height: showsNotchSideHUD
                ? panelState.topInset
                : showsExpandedHUD
                ? hudHeight
                : usesExpandedLayout
                ? expandedPanelHeight
                : panelState.topInset + hoverPreviewHeight
        )
        let expandedArtworkOffset = CGPoint(
            x: NotchLayout.expandedHorizontalPadding,
            y: 42
        )

        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                Color.black

                if !showsExpandedHUD {
                    NotchBackdrop(
                        topCornerRadius: topCornerRadius,
                        bottomCornerRadius: bottomCornerRadius,
                        artwork: musicMonitor.snapshot?.artwork,
                        accent: accent,
                        bottomBackground: bottomBackground,
                        isPlaying: isPlaying,
                        backgroundEnabled: notchBackgroundEnabled,
                        alwaysVisible: notchBackgroundAlwaysVisible,
                        backgroundEffect: selectedNotchBackgroundEffect,
                        spectrumLevels: audioSpectrumMonitor.levels,
                        isExpanded: usesExpandedLayout,
                        topInset: panelState.topInset
                    )
                }

                if let snapshot = musicMonitor.snapshot,
                   let artwork = snapshot.artwork,
                   !hasSystemHUD,
                   !systemActivityMonitor.isScreenLocked,
                   !isPlaying,
                   usesExpandedLayout
                    || compactPresentation == .playback
                    || compactPresentation == nil,
                   !usesExpandedLayout
                    || selectedContentPage == .music
                    || outgoingContentPage == .music {
                    let compactGlow = !showsWatchFaceInMusic
                    let glowSize: CGFloat = panelState.isExpanded
                        ? currentExpandedArtworkSize
                        : 22
                    let glowOffset = panelState.isExpanded
                        ? expandedArtworkOffset
                        : CGPoint(
                            x: topCornerRadius + compactOuterPadding,
                            y: (size.height - glowSize) / 2
                        )
                    ZStack(alignment: .topLeading) {
                        Color.clear

                        Image(nsImage: artwork)
                            .resizable()
                            .scaledToFill()
                            .frame(
                                width: glowSize,
                                height: glowSize
                            )
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 12,
                                    style: .continuous
                                )
                            )
                            .scaleEffect(
                                x: compactGlow ? 1.10 : 1.24,
                                y: compactGlow ? 1.04 : 1.24
                            )
                            .saturation(1.45)
                            .contrast(1.06)
                            .brightness(0.06)
                            .blur(radius: compactGlow ? 6 : 12)
                            .opacity(
                                panelState.isExpanded
                                    ? (compactGlow ? 0.60 : 0.72)
                                    : 0
                            )
                            .blendMode(.screen)
                            .offset(
                                x: glowOffset.x,
                                y: glowOffset.y
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
                    .offset(
                        x: contentPageOffset(
                            for: .music,
                            width: size.width
                        )
                    )
                    .opacity(contentPageOpacity(for: .music))
                    .animation(
                        .easeInOut(duration: 0.46),
                        value: snapshot.trackID
                    )
                    .animation(
                        artworkAnimation,
                        value: panelState.isExpanded
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
                } else {
                    ZStack {
                        if usesExpandedLayout {
                            if let presentation = systemHUDPresentation,
                               showsExpandedHUD {
                                SystemHUDView(
                                    presentation: presentation,
                                    style: selectedSystemHUDStyle,
                                    albumAccent: accent
                                )
                                .padding(.top, 10)
                                .padding(.bottom, 10)
                                .transition(expandedContentTransition)
                            } else {
                                expandedPageContent(width: size.width)
                                    .transition(pageContentTransition)
                                    .animation(
                                        expansionAnimation,
                                        value: panelState.isExpanded
                                    )
                                    .overlay {
                                        if panelState.isExpanded,
                                           !systemActivityMonitor.isScreenLocked {
                                            TrackpadPageSwipeView(
                                                excludedLeadingWidth:
                                                    calendarDateWheelExcludedWidth(
                                                        pageWidth: size.width
                                                    ),
                                                onSwipe: { direction in
                                                    swipeContentPage(direction)
                                                }
                                            )
                                            .frame(
                                                width: size.width,
                                                height: size.height
                                            )
                                            .allowsHitTesting(false)
                                        }
                                    }
                            }
                        } else if showsCompactActivity {
                            compactContent(
                                deviceConnection: deviceConnection,
                                width: size.width,
                                cornerInset: topCornerRadius
                            )
                            .transition(compactContentTransition)
                        }
                    }
                    .animation(
                        hudRevealAnimation,
                        value: hasSystemHUD
                    )
                }

                if let snapshot = musicMonitor.snapshot,
                   !hasSystemHUD,
                   !systemActivityMonitor.isScreenLocked,
                   usesExpandedLayout
                    || compactPresentation == .playback
                    || compactPresentation == nil,
                   !usesExpandedLayout
                    || selectedContentPage == .music
                    || outgoingContentPage == .music {
                    let artworkSize: CGFloat = panelState.isExpanded
                        ? currentExpandedArtworkSize
                        : 22
                    let artworkSwipeDistance = panelState.isExpanded
                        ? currentExpandedArtworkSize + 12
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
                    .opacity(
                        showsArtwork
                            ? contentPageOpacity(for: .music)
                            : 0
                    )
                    .allowsHitTesting(showsArtwork)
                }

                if usesExpandedLayout && !hasSystemHUD {
                    expandedTrailingControls
                        .padding(.top, 4)
                        .padding(
                            .trailing,
                            NotchLayout.expandedHorizontalPadding
                        )
                        .frame(
                            width: size.width,
                            height: size.height,
                            alignment: .topTrailing
                        )
                        .transition(expandedModuleTransition)
                        .animation(
                            expansionAnimation,
                            value: panelState.isExpanded
                        )

                    expandedPageSwitcher
                        .padding(.top, 4)
                        .padding(
                            .leading,
                            NotchLayout.expandedHorizontalPadding
                        )
                        .frame(
                            width: size.width,
                            height: size.height,
                            alignment: .topLeading
                        )
                        .transition(expandedModuleTransition)
                        .animation(
                            expansionAnimation,
                            value: panelState.isExpanded
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
            .shadow(
                color: showsExpandedHUD
                    ? .clear
                    : .black.opacity(
                        panelState.isHovering || panelState.isExpanded ? 0.55 : 0
                    ),
                radius: 22,
                y: 0
            )
            .overlay {
                if !showsExpandedHUD {
                    NotchShape(
                        topCornerRadius: topCornerRadius,
                        bottomCornerRadius: bottomCornerRadius
                    )
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                }
            }
            .overlay(alignment: .topLeading) {
                if isNotchPreviewActive {
                    notchPreview(
                        width: size.width,
                        topCornerRadius: topCornerRadius,
                        bottomCornerRadius: bottomCornerRadius
                    )
                } else if showsPhysicalNotchOutline {
                    physicalNotchOutline(width: size.width)
                }
            }
            .contentShape(
                NotchShape(
                    topCornerRadius: topCornerRadius,
                    bottomCornerRadius: bottomCornerRadius
                )
            )
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard showsVolumeSlider,
                              !volumeSliderPillFrame(
                                  panelWidth: size.width
                              ).contains(value.location)
                        else {
                            return
                        }
                        withAnimation(volumeSliderAnimation) {
                            showsVolumeSlider = false
                        }
                    }
            )
            .onHover { hovering in
                guard !systemActivityMonitor.isScreenLocked else { return }
                panelState.setHovering(hovering)
            }
            .onChange(of: usesExpandedLayout) { _, expanded in
                if !expanded {
                    showsVolumeSlider = false
                }
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
            notchTransitionAnimation(
                opening: panelState.isHoverPreviewActive
            ),
            value: panelState.isHoverPreviewActive
        )
        .animation(
            notchTransitionAnimation(
                opening: panelState.isHovering || panelState.isExpanded
            ),
            value: panelState.isHovering
        )
        .animation(
            expansionAnimation,
            value: panelState.isExpanded
        )
        .animation(
            watchFaceVisibilityAnimation,
            value: showsWatchFaceInMusic
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
            systemHUDPresentationAnimation,
            value: systemHUDController.presentation
        )
        .animation(
            compactPresentationAnimation,
            value: compactPresentation
        )
        .onAppear {
            panelState.updateVisibleSize(size)
        }
        .onChange(of: size) { _, newSize in
            panelState.updateVisibleSize(newSize)
        }
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

    private static let notchExpansionSpring = Animation.spring(
        response: 0.44,
        dampingFraction: 0.68,
        blendDuration: 0
    )

    private static let notchCollapseSpring = Animation.spring(
        response: 0.44,
        dampingFraction: 0.96,
        blendDuration: 0
    )

    private var expansionAnimation: Animation {
        notchTransitionAnimation(opening: panelState.isExpanded)
    }

    private var watchFaceVisibilityAnimation: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.18)
        }
        return .spring(response: 0.36, dampingFraction: 0.86)
    }

    private var systemActivityAnimation: Animation {
        notchTransitionAnimation(
            opening: panelState.isExpanded
                || systemHUDController.presentation != nil
                || compactPresentation != nil
        )
    }

    private var systemHUDPresentationAnimation: Animation {
        notchTransitionAnimation(
            opening: systemHUDController.presentation != nil
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

    private var pageContentTransition: AnyTransition {
        selectedContentPage == .calendar
            ? expandedContentFadeTransition
            : expandedModuleTransition
    }

    private var expandedContentFadeTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }

        return .asymmetric(
            insertion: notchSuckInsertion,
            removal: notchSuckRemoval
        )
    }

    private var expandedModuleTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }

        return .asymmetric(
            insertion: AnyTransition.modifier(
                active: NotchScaleTransitionModifier(
                    scale: 0.25,
                    anchor: .top
                ),
                identity: NotchScaleTransitionModifier(
                    scale: 1,
                    anchor: .top
                )
            ),
            removal: notchSuckRemoval
        )
    }

    private var notchSuckInsertion: AnyTransition {
        AnyTransition.modifier(
            active: NotchBlurTransitionModifier(radius: 7),
            identity: NotchBlurTransitionModifier(radius: 0)
        )
        .combined(with: .opacity)
        .combined(
            with: AnyTransition.modifier(
                active: NotchScaleTransitionModifier(
                    scale: 0.25,
                    anchor: .top
                ),
                identity: NotchScaleTransitionModifier(
                    scale: 1,
                    anchor: .top
                )
            )
        )
    }

    private var notchSuckRemoval: AnyTransition {
        .opacity.combined(
            with: AnyTransition.modifier(
                active: NotchScaleTransitionModifier(
                    scale: 0.25,
                    anchor: .top
                ),
                identity: NotchScaleTransitionModifier(
                    scale: 1,
                    anchor: .top
                )
            )
        )
    }

    private func contentRevealAnimation(expanded: Bool) -> Animation {
        if reduceMotion {
            return .easeOut(duration: 0.18)
        }

        if expanded {
            return .easeOut(duration: 0.42).delay(0.04)
        }
        return .easeIn(duration: 0.14)
    }

    private var hudRevealAnimation: Animation {
        let hasSystemHUD =
            deviceConnectionMonitor.presentation == nil
            && !systemActivityMonitor.isScreenLocked
            && systemHUDController.presentation != nil

        return contentRevealAnimation(expanded: hasSystemHUD)
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
        notchTransitionAnimation(opening: compactPresentation != nil)
    }

    private var compactContentTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }

        return .asymmetric(
            insertion: .opacity,
            removal: .scale(scale: 0.08, anchor: .center)
        )
    }

    private func notchTransitionAnimation(opening: Bool) -> Animation {
        if reduceMotion {
            return .easeOut(duration: 0.18)
        }
        return opening
            ? Self.notchExpansionSpring
            : Self.notchCollapseSpring
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

    /// Red calibration overlay shown while the notch size is being tuned.
    /// It reflects the pending values only; the panel itself keeps the
    /// committed geometry until the user confirms.
    private func notchPreview(
        width: CGFloat,
        topCornerRadius: CGFloat,
        bottomCornerRadius: CGFloat
    ) -> some View {
        let widthDelta = CGFloat(notchPreviewWidth - notchWidthAdjustment)
        let heightDelta = CGFloat(notchPreviewHeight - notchHeightAdjustment)
        let bodyWidth = max(panelState.notchWidth + widthDelta, 8)
        let rectHeight = max(panelState.topInset + heightDelta, 8)
        let shapeWidth = bodyWidth + topCornerRadius * 2
        let rectX = (width - shapeWidth) / 2
        let shape = NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius
        )

        return ZStack {
            shape
                .fill(Color.red.opacity(0.18))

            shape
                .stroke(
                    Color.red.opacity(0.92),
                    style: StrokeStyle(
                        lineWidth: 1.5,
                        dash: [4, 3]
                    )
                )

            Text(
                "\(Int(bodyWidth.rounded())) × \(Int(rectHeight.rounded()))"
            )
            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(Color.red.opacity(0.85), in: Capsule())
        }
        .frame(width: shapeWidth, height: rectHeight)
        .offset(x: rectX)
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
                        CompactScreenStateIcon(activity: activity)
                            .transition(.identity)
                    }
                case .device:
                    if let deviceConnection {
                        AirPodsStatusIcon(
                            model: deviceConnection.model,
                            size: 30,
                            content: soundHUDContent
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
                        CompactBatteryRing(
                            level: deviceConnectionBatteryLevel(
                                deviceConnection
                            )
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("AirPods 电量")
                        .accessibilityValue(
                            deviceConnectionBatteryText(deviceConnection)
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
                case .lock:
                    if systemActivityMonitor.showsUnlockFailure {
                        CompactUnlockResultIcon(
                            systemName: "xmark",
                            tint: Color(red: 1.0, green: 0.36, blue: 0.36),
                            label: "解锁失败",
                            wobbles: true
                        )
                        .transition(unlockResultTransition)
                    }
                case .unlock:
                    CompactUnlockCheckIcon(
                        tint: Color(red: 0.33, green: 0.86, blue: 0.61),
                        label: "屏幕已解锁"
                    )
                    .transition(unlockResultTransition)
                case nil:
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

    private func deviceConnectionBatteryText(
        _ presentation: DeviceConnectionPresentation
    ) -> String {
        guard let batteryLevel = presentation.batteryLevel else {
            return "--"
        }
        return "\(Int((batteryLevel * 100).rounded()))%"
    }

    private func deviceConnectionBatteryLevel(
        _ presentation: DeviceConnectionPresentation
    ) -> Double {
        guard let batteryLevel = presentation.batteryLevel else {
            return 0
        }
        return min(max(batteryLevel, 0), 1)
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

    private var unlockResultTransition: AnyTransition {
        .asymmetric(
            insertion: reduceMotion ? .opacity : .identity,
            removal: reduceMotion
                ? .opacity
                : .scale(scale: 0.05, anchor: .center)
        )
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
                    switchContentPage(to: page)
                } label: {
                    Image(systemName: page.systemImage)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(
                            isSelected
                                ? Color.white
                                : Color.white.opacity(0.42)
                        )
                        .frame(width: 24, height: 20)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(page.title)
                .accessibilityLabel(page.title)
            }
        }
    }

    private func switchContentPage(
        to page: NotchContentPage,
        direction: ContentPageTransitionDirection? = nil
    ) {
        let currentIndex =
            NotchContentPage.allCases.firstIndex(
                of: selectedContentPage
            ) ?? 0
        let targetIndex =
            NotchContentPage.allCases.firstIndex(of: page) ?? currentIndex

        contentPageTransitionDirection =
            direction
            ?? (targetIndex > currentIndex ? .forward : .backward)
        outgoingContentPage = selectedContentPage
        contentPageTransitionProgress = 0
        selectedContentPage = page
        pageSwitchTask?.cancel()
        pageSwitchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 16_000_000)
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
    }

    private func swipeContentPage(
        _ direction: ContentPageTransitionDirection
    ) {
        guard outgoingContentPage == nil else { return }
        let target: NotchContentPage =
            selectedContentPage == .music ? .calendar : .music
        switchContentPage(to: target, direction: direction)
    }

    private func calendarDateWheelExcludedWidth(
        pageWidth: CGFloat
    ) -> CGFloat {
        guard selectedContentPage == .calendar else { return 0 }
        let contentWidth =
            pageWidth - NotchLayout.expandedHorizontalPadding * 2
        let monthWidth = min(max(contentWidth * 0.45, 186), 218)
        return NotchLayout.expandedHorizontalPadding + monthWidth
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
            return 28
        case .device:
            return 48
        case .activity(let id):
            let label = compactSystemActivities.first {
                $0.id == id
            }?.name
            let labelWidth = label.map(compactLabelWidth) ?? 0
            return min(max(16, labelWidth) + 16, 170)
        case .playback:
            return 34
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
            String(systemActivityMonitor.showsUnlockFailure),
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
            CalendarIslandView(
                accent: accent,
                width: width
                    - NotchLayout.expandedHorizontalPadding * 2
            )
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
        let watchFaceWidth = showsWatchFaceInMusic ? expandedWatchFaceSize : 0
        let columnSpacing = showsWatchFaceInMusic
            ? NotchLayout.expandedColumnSpacing
            : 0
        let musicWidth = max(
            0,
            width
                - NotchLayout.expandedHorizontalPadding * 2
                - columnSpacing
                - watchFaceWidth
        )

        return HStack(
            alignment: .top,
            spacing: columnSpacing
        ) {
            Group {
                ZStack(alignment: .topLeading) {
                    if let snapshot = musicMonitor.snapshot {
                        if showsWatchFaceInMusic {
                            nowPlaying(snapshot, musicWidth: musicWidth)
                                .transition(.opacity)
                        } else {
                            compactNowPlaying(
                                snapshot,
                                musicWidth: musicWidth
                            )
                            .transition(.opacity)
                        }
                    } else {
                        emptyState
                            .transition(.opacity)
                    }
                }
            }
            .frame(width: musicWidth)
            .frame(maxHeight: .infinity, alignment: .topLeading)

            if showsWatchFaceInMusic {
                WatchFaceView(
                    style: selectedWatchFace,
                    accent: accent,
                    size: expandedWatchFaceSize
                )
                .hoverParallax(size: expandedWatchFaceSize)
                .transition(
                    .opacity.combined(
                        with: .scale(scale: 0.86, anchor: .trailing)
                    )
                )
            }
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

    private var currentExpandedArtworkSize: CGFloat {
        showsWatchFaceInMusic
            ? expandedArtworkSize
            : compactExpandedArtworkSize
    }

    private var expandedPanelHeight: CGFloat {
        showsWatchFaceInMusic
            ? NotchLayout.expandedHeight
            : NotchLayout.compactExpandedHeight
    }

    private var expandedPanelWidth: CGFloat {
        let width = NotchLayout.expandedWidth(
            notchWidth: panelState.notchWidth
        )
        guard !showsWatchFaceInMusic else {
            return width
        }
        return width - expandedWatchFaceSize / 2
    }

    private var selectedSystemHUDStyle: SystemHUDStyle {
        SystemHUDStyle(rawValue: systemHUDStyleRaw) ?? .customOSD
    }

    private func nowPlaying(
        _ snapshot: MusicSnapshot,
        musicWidth: CGFloat
    ) -> some View {
        let rowHeight = expandedArtworkSize / 4
        let textColumnWidth = max(
            0,
            musicWidth - expandedArtworkSize - 14
        )

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

                    playbackControls(
                        snapshot,
                        width: textColumnWidth
                    )
                    .frame(height: rowHeight)
                }
                .frame(
                    width: textColumnWidth,
                    height: expandedArtworkSize,
                    alignment: .topLeading
                )
            }
            .frame(height: expandedArtworkSize, alignment: .top)

            Spacer(minLength: 6)

            playbackProgress(snapshot)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func compactNowPlaying(
        _ snapshot: MusicSnapshot,
        musicWidth: CGFloat
    ) -> some View {
        let artworkSize = compactExpandedArtworkSize
        let artworkSpacing: CGFloat = 16
        let textColumnWidth = max(
            0,
            musicWidth - artworkSize - artworkSpacing
        )
        let rowHeight = compactExpandedRowHeight

        return HStack(alignment: .top, spacing: artworkSpacing) {
            Color.clear
                .frame(width: artworkSize, height: artworkSize)

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

                playbackControls(
                    snapshot,
                    width: textColumnWidth
                )
                .frame(height: 28)

                playbackProgress(snapshot)
                    .frame(height: 28)
            }
            .frame(width: textColumnWidth, alignment: .topLeading)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
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

    private func playbackControls(
        _ snapshot: MusicSnapshot,
        width: CGFloat
    ) -> some View {
        let layout = MusicControlLayoutSettings.decode(musicControlLayoutRaw)
        let items = layout.compactMap { $0 }
        let spacing = musicControlSpacing(
            width: width,
            itemCount: items.count
        )
        let volumeInset = musicControlVolumeInset(
            items: items,
            spacing: spacing
        )

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
        .overlay(alignment: .trailing) {
            if showsVolumeSlider {
                volumeSliderPill(snapshot)
                    .offset(x: -volumeInset)
                    .transition(
                        .opacity.combined(
                            with: .scale(scale: 0.92, anchor: .trailing)
                        )
                    )
            }
        }
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
            PlaybackButton(
                systemName: volumeIcon(snapshot.volume),
                label: "音量",
                tint: bottomBackground,
                fontSize: 12
            ) {
                withAnimation(volumeSliderAnimation) {
                    showsVolumeSlider.toggle()
                }
            }
        }
    }

    private var volumeSliderAnimation: Animation {
        .spring(response: 0.28, dampingFraction: 0.84)
    }

    private func musicControlSpacing(
        width: CGFloat,
        itemCount: Int
    ) -> CGFloat {
        guard itemCount > 1 else { return 0 }
        return max(
            0,
            (width - 28 * CGFloat(itemCount)) / CGFloat(itemCount - 1)
        )
    }

    private func musicControlVolumeInset(
        items: [MusicControlItem],
        spacing: CGFloat
    ) -> CGFloat {
        guard let index = items.firstIndex(of: .volume) else { return 0 }
        return spacing * CGFloat(items.count - 1 - index)
    }

    private func volumeSliderPillFrame(
        panelWidth: CGFloat
    ) -> CGRect {
        let watchFaceWidth = showsWatchFaceInMusic ? expandedWatchFaceSize : 0
        let columnSpacing = showsWatchFaceInMusic
            ? NotchLayout.expandedColumnSpacing
            : 0
        let musicWidth = max(
            0,
            panelWidth
                - NotchLayout.expandedHorizontalPadding * 2
                - columnSpacing
                - watchFaceWidth
        )
        let artworkWidth = showsWatchFaceInMusic
            ? expandedArtworkSize
            : compactExpandedArtworkSize
        let artworkSpacing: CGFloat = showsWatchFaceInMusic ? 14 : 16
        let textColumnWidth = max(
            0,
            musicWidth - artworkWidth - artworkSpacing
        )
        let items = MusicControlLayoutSettings
            .decode(musicControlLayoutRaw)
            .compactMap { $0 }
        let spacing = musicControlSpacing(
            width: textColumnWidth,
            itemCount: items.count
        )
        let volumeInset = musicControlVolumeInset(
            items: items,
            spacing: spacing
        )
        let rowHeight = showsWatchFaceInMusic
            ? expandedArtworkSize / 4
            : compactExpandedRowHeight

        return CGRect(
            x: NotchLayout.expandedHorizontalPadding
                + artworkWidth
                + artworkSpacing
                + textColumnWidth
                - volumeSliderPillWidth
                - volumeInset,
            y: NotchLayout.expandedTopPadding + rowHeight * 3 - 2,
            width: volumeSliderPillWidth,
            height: 28
        )
    }

    private func volumeSliderPill(
        _ snapshot: MusicSnapshot
    ) -> some View {
        HStack(spacing: 6) {
            volumeSliderBar(snapshot)

            PlaybackButton(
                systemName: volumeIcon(snapshot.volume),
                label: "音量",
                tint: bottomBackground,
                fontSize: 12
            ) {
                withAnimation(volumeSliderAnimation) {
                    showsVolumeSlider = false
                }
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 2)
        .frame(width: volumeSliderPillWidth, height: 28)
        .background {
            Capsule(style: .continuous)
                .fill(Color(white: 0.16))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 0.5)
                }
        }
    }

    private func volumeSliderBar(
        _ snapshot: MusicSnapshot
    ) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: 7)

                Capsule()
                    .fill(Color.white)
                    .frame(
                        width: max(
                            7,
                            geometry.size.width
                                * CGFloat(snapshot.volume)
                        ),
                        height: 7
                    )
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = min(
                            max(
                                value.location.x / geometry.size.width,
                                0
                            ),
                            1
                        )
                        musicMonitor.setVolume(Double(fraction))
                    }
            )
        }
        .frame(width: 62, height: 28)
        .accessibilityElement()
        .accessibilityLabel("Apple Music 音量")
        .accessibilityValue(Text("\(Int(snapshot.volume * 100))%"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                musicMonitor.setVolume(min(snapshot.volume + 0.05, 1))
            case .decrement:
                musicMonitor.setVolume(max(snapshot.volume - 0.05, 0))
            @unknown default:
                break
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
        let presentation = emptyStatePresentation

        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.08))

                Image(systemName: presentation.icon)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(.white.opacity(0.66))
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 5) {
                Text(presentation.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text(presentation.description)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.54))
                    .lineLimit(2)

                Button(
                    presentation.actionTitle,
                    action: presentation.action
                )
                .buttonStyle(NotchActionButtonStyle())
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var emptyStatePresentation: EmptyStatePresentation {
        if !musicMonitor.isConnected {
            return EmptyStatePresentation(
                title: "连接 Apple Music",
                description: "授权后，刘海会显示当前播放的歌曲。",
                icon: "link",
                actionTitle: "连接",
                action: { musicMonitor.connect() }
            )
        }
        if musicMonitor.needsPermission {
            return EmptyStatePresentation(
                title: "需要自动化权限",
                description: "在系统设置中允许 NotchMusic 控制 Apple Music。",
                icon: "lock.open",
                actionTitle: "打开系统设置",
                action: { musicMonitor.openAutomationSettings() }
            )
        }
        if !musicMonitor.isMusicRunning {
            return EmptyStatePresentation(
                title: "Apple Music 未运行",
                description: "播放音乐后会自动显示在这里。",
                icon: "music.note",
                actionTitle: "打开 Apple Music",
                action: { musicMonitor.openAppleMusic() }
            )
        }
        if let errorMessage = musicMonitor.errorMessage {
            return EmptyStatePresentation(
                title: "读取失败",
                description: errorMessage,
                icon: "exclamationmark.triangle",
                actionTitle: "重试",
                action: { musicMonitor.refreshNow() }
            )
        }
        return EmptyStatePresentation(
            title: "没有正在播放的音乐",
            description: "在 Apple Music 中选择一首歌曲。",
            icon: "waveform",
            actionTitle: "刷新",
            action: { musicMonitor.refreshNow() }
        )
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
