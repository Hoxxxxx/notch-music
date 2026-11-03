import AppKit
import Combine
import Foundation

enum TrackTransitionDirection {
    case forward
    case backward
}

@MainActor
final class MusicMonitor: ObservableObject {
    @Published private(set) var snapshot: MusicSnapshot?
    @Published private(set) var trackTransitionDirection:
        TrackTransitionDirection = .forward
    @Published private(set) var isConnected = false
    @Published private(set) var isMusicRunning = false
    @Published private(set) var needsPermission = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isSendingCommand = false

    private let client = AppleMusicClient()
    private let connectionKey = "NotchMusic.didConnectAppleMusic"
    private var pollTask: Task<Void, Never>?
    private var volumeTask: Task<Void, Never>?
    private var pendingVolume: Double?
    private var stateRevision = 0
    private var pendingPlaybackState: Bool?
    private var pendingPlaybackStateDeadline: Date?
    private var pendingShuffleState: Bool?
    private var pendingShuffleStateDeadline: Date?
    private var pendingTrackTransitionDirection: TrackTransitionDirection?
    private var pendingTrackTransitionDeadline: Date?

    init() {
        isConnected = UserDefaults.standard.bool(forKey: connectionKey)
        if isConnected {
            startPolling()
        }
    }

    func connect() {
        guard !isConnected else {
            refreshNow()
            return
        }

        isConnected = true
        UserDefaults.standard.set(true, forKey: connectionKey)
        startPolling()
    }

    func disconnect() {
        pollTask?.cancel()
        pollTask = nil
        volumeTask?.cancel()
        volumeTask = nil
        pendingVolume = nil
        pendingPlaybackState = nil
        pendingPlaybackStateDeadline = nil
        pendingShuffleState = nil
        pendingShuffleStateDeadline = nil
        pendingTrackTransitionDirection = nil
        pendingTrackTransitionDeadline = nil
        isConnected = false
        UserDefaults.standard.set(false, forKey: connectionKey)
        snapshot = nil
        needsPermission = false
        errorMessage = nil
    }

    func refreshNow() {
        Task {
            await refresh()
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        volumeTask?.cancel()
        volumeTask = nil
        pendingVolume = nil
    }

    func openAppleMusic() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") else {
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
    }

    func openAutomationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func previousTrack() {
        guard isConnected, isMusicRunning, !isSendingCommand else { return }
        pendingTrackTransitionDirection = .backward
        pendingTrackTransitionDeadline = Date().addingTimeInterval(2)
        perform(.previousTrack)
    }

    func toggleShuffle() {
        guard isConnected,
              isMusicRunning,
              !isSendingCommand,
              let snapshot else {
            perform(.toggleShuffle)
            return
        }

        let targetState = !snapshot.isShuffleEnabled
        pendingShuffleState = targetState
        pendingShuffleStateDeadline = Date().addingTimeInterval(1)
        self.snapshot = snapshot.updating(isShuffleEnabled: targetState)
        perform(.toggleShuffle, rollbackSnapshot: snapshot)
    }

    func togglePlayPause() {
        guard isConnected,
              isMusicRunning,
              !isSendingCommand,
              let snapshot else {
            perform(.togglePlayPause)
            return
        }

        let targetState = !snapshot.isPlaying
        pendingPlaybackState = targetState
        pendingPlaybackStateDeadline = Date().addingTimeInterval(1)
        let currentPosition = snapshot.elapsed(at: Date())
        self.snapshot = snapshot.updating(
            position: currentPosition,
            isPlaying: targetState
        )
        perform(.togglePlayPause, rollbackSnapshot: snapshot)
    }

    func nextTrack() {
        guard isConnected, isMusicRunning, !isSendingCommand else { return }
        pendingTrackTransitionDirection = .forward
        pendingTrackTransitionDeadline = Date().addingTimeInterval(2)
        perform(.nextTrack)
    }

    func seek(to position: TimeInterval) {
        guard let snapshot, snapshot.duration > 0 else { return }
        let clamped = min(max(position, 0), snapshot.duration)
        self.snapshot = snapshot.updating(position: clamped)
        perform(.seek(to: clamped))
    }

    func setVolume(_ volume: Double) {
        guard isConnected, isMusicRunning, let snapshot else { return }
        let clamped = min(max(volume, 0), 1)
        stateRevision &+= 1
        self.snapshot = snapshot.updating(volume: clamped)
        pendingVolume = clamped

        guard volumeTask == nil else { return }
        volumeTask = Task {
            await flushVolumeCommands()
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refresh()
                let delay: UInt64 = self.needsPermission ? 8 : 2
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            }
        }
    }

    private func refresh(afterTrackChange: Bool = false) async {
        guard isConnected, !isSendingCommand else { return }
        let revision = stateRevision

        let running = Self.appleMusicIsRunning
        isMusicRunning = running
        guard running else {
            snapshot = nil
            needsPermission = false
            errorMessage = nil
            return
        }

        let result = afterTrackChange
            ? await client.readAfterTrackChange()
            : await client.read()
        guard !Task.isCancelled,
              !isSendingCommand,
              revision == stateRevision else { return }

        switch result {
        case .success(let value):
            needsPermission = false
            errorMessage = nil
            if let value {
                let resolvedPlaybackState = resolvedPlaybackState(
                    actual: value.isPlaying
                )
                let resolvedShuffleState = resolvedShuffleState(
                    actual: value.isShuffleEnabled
                )
                if let currentTrackID = snapshot?.trackID,
                   currentTrackID != value.trackID {
                    let deadline = pendingTrackTransitionDeadline
                    let hasPendingDirection =
                        deadline.map { $0 >= Date() } == true
                    trackTransitionDirection = hasPendingDirection
                        ? pendingTrackTransitionDirection ?? .forward
                        : .forward
                    pendingTrackTransitionDirection = nil
                    pendingTrackTransitionDeadline = nil
                }
                snapshot = MusicSnapshot(
                    trackID: value.trackID,
                    title: value.title,
                    artist: value.artist,
                    album: value.album,
                    duration: value.duration,
                    position: value.position,
                    isPlaying: resolvedPlaybackState,
                    volume: value.volume,
                    isShuffleEnabled: resolvedShuffleState,
                    artwork: value.artworkData.flatMap(NSImage.init(data:)),
                    sampledAt: Date()
                )
            } else {
                snapshot = nil
            }
        case .failure(let error):
            snapshot = nil
            switch error {
            case .permissionDenied:
                needsPermission = true
                errorMessage = nil
            case .scriptError(let message):
                needsPermission = false
                errorMessage = message
            }
        }
    }

    private func perform(
        _ command: AppleMusicCommand,
        rollbackSnapshot: MusicSnapshot? = nil
    ) {
        guard isConnected, isMusicRunning, !isSendingCommand else { return }
        stateRevision &+= 1
        isSendingCommand = true

        Task {
            let result = await client.send(command)
            isSendingCommand = false
            guard !Task.isCancelled else { return }

            switch result {
            case .success:
                switch command {
                case .previousTrack, .nextTrack:
                    await refresh(afterTrackChange: true)
                default:
                    await refresh()
                }
            case .failure(let error):
                pendingTrackTransitionDirection = nil
                pendingTrackTransitionDeadline = nil
                if let rollbackSnapshot {
                    snapshot = rollbackSnapshot
                    pendingPlaybackState = nil
                    pendingPlaybackStateDeadline = nil
                    pendingShuffleState = nil
                    pendingShuffleStateDeadline = nil
                }
                handleCommandFailure(error)
            }
        }
    }

    private func flushVolumeCommands() async {
        while !Task.isCancelled, let volume = pendingVolume {
            pendingVolume = nil
            let result = await client.send(.setVolume(volume))
            guard !Task.isCancelled else { return }

            if case .failure(let error) = result {
                handleCommandFailure(error)
                break
            }
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        volumeTask = nil
    }

    private func handleCommandFailure(_ error: AppleMusicClientError) {
        switch error {
        case .permissionDenied:
            needsPermission = true
            errorMessage = nil
        case .scriptError(let message):
            errorMessage = message
        }
    }

    private func resolvedPlaybackState(actual: Bool) -> Bool {
        guard let pendingPlaybackState else { return actual }

        let expired = Date() >= (pendingPlaybackStateDeadline ?? .distantPast)
        if actual == pendingPlaybackState || expired {
            self.pendingPlaybackState = nil
            pendingPlaybackStateDeadline = nil
            return actual
        }

        return pendingPlaybackState
    }

    private func resolvedShuffleState(actual: Bool) -> Bool {
        guard let pendingShuffleState else { return actual }

        let expired = Date() >= (pendingShuffleStateDeadline ?? .distantPast)
        if actual == pendingShuffleState || expired {
            self.pendingShuffleState = nil
            pendingShuffleStateDeadline = nil
            return actual
        }

        return pendingShuffleState
    }

    private static var appleMusicIsRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.Music"
        }
    }
}
