import AppKit
import Combine
import Foundation

@MainActor
final class MusicMonitor: ObservableObject {
    @Published private(set) var snapshot: MusicSnapshot?
    @Published private(set) var isConnected = false
    @Published private(set) var isMusicRunning = false
    @Published private(set) var needsPermission = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isSendingCommand = false

    private let client = AppleMusicClient()
    private let connectionKey = "NotchMusic.didConnectAppleMusic"
    private var pollTask: Task<Void, Never>?

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
        perform(.previousTrack)
    }

    func togglePlayPause() {
        perform(.togglePlayPause)
    }

    func nextTrack() {
        perform(.nextTrack)
    }

    func seek(to position: TimeInterval) {
        guard let snapshot, snapshot.duration > 0 else { return }
        let clamped = min(max(position, 0), snapshot.duration)
        self.snapshot = snapshot.updatingPosition(clamped)
        perform(.seek(to: clamped))
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

    private func refresh() async {
        guard isConnected else { return }

        let running = Self.appleMusicIsRunning
        isMusicRunning = running
        guard running else {
            snapshot = nil
            needsPermission = false
            errorMessage = nil
            return
        }

        let result = await client.read()
        guard !Task.isCancelled else { return }

        switch result {
        case .success(let value):
            needsPermission = false
            errorMessage = nil
            if let value {
                snapshot = MusicSnapshot(
                    trackID: value.trackID,
                    title: value.title,
                    artist: value.artist,
                    album: value.album,
                    duration: value.duration,
                    position: value.position,
                    isPlaying: value.isPlaying,
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

    private func perform(_ command: AppleMusicCommand) {
        guard isConnected, isMusicRunning, !isSendingCommand else { return }
        isSendingCommand = true

        Task {
            let result = await client.send(command)
            isSendingCommand = false
            guard !Task.isCancelled else { return }

            switch result {
            case .success:
                await refresh()
            case .failure(let error):
                switch error {
                case .permissionDenied:
                    needsPermission = true
                    errorMessage = nil
                case .scriptError(let message):
                    errorMessage = message
                }
            }
        }
    }

    private static var appleMusicIsRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.Music"
        }
    }
}
