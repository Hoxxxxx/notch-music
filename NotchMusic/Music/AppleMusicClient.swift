import AppKit
import Foundation

struct MusicReadResult: Sendable {
    let trackID: String
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let position: TimeInterval
    let isPlaying: Bool
    let volume: Double
    let isShuffleEnabled: Bool
    let artworkData: Data?
}

enum AppleMusicClientError: Error, Sendable {
    case permissionDenied
    case scriptError(String)
}

enum AppleMusicCommand: Sendable {
    case previousTrack
    case toggleShuffle
    case togglePlayPause
    case nextTrack
    case seek(to: TimeInterval)
    case setVolume(Double)

    fileprivate var script: String {
        switch self {
        case .previousTrack:
            return """
            tell application "Music"
                set previousTrackID to ""
                try
                    set previousTrackID to persistent ID of current track
                end try
                previous track
                repeat 20 times
                    delay 0.05
                    try
                        if (persistent ID of current track) is not previousTrackID then exit repeat
                    end try
                end repeat
            end tell
            """
        case .toggleShuffle:
            return """
            tell application "Music"
                if shuffle enabled then
                    set shuffle enabled to false
                else
                    set shuffle enabled to true
                end if
            end tell
            """
        case .togglePlayPause:
            return """
            tell application "Music"
                playpause
            end tell
            """
        case .nextTrack:
            return """
            tell application "Music"
                set previousTrackID to ""
                try
                    set previousTrackID to persistent ID of current track
                end try
                next track
                repeat 20 times
                    delay 0.05
                    try
                        if (persistent ID of current track) is not previousTrackID then exit repeat
                    end try
                end repeat
            end tell
            """
        case .seek(let position):
            let value = String(
                format: "%.3f",
                locale: Locale(identifier: "en_US_POSIX"),
                position
            )
            return """
            tell application "Music"
                set player position to \(value)
            end tell
            """
        case .setVolume(let volume):
            let percentage = Int((min(max(volume, 0), 1) * 100).rounded())
            return """
            tell application "Music"
                set sound volume to \(percentage)
            end tell
            """
        }
    }
}

final class AppleMusicClient: @unchecked Sendable {
    private let readQueue = DispatchQueue(
        label: "NotchMusic.AppleMusicClient.read",
        qos: .utility
    )
    private let commandQueue = DispatchQueue(
        label: "NotchMusic.AppleMusicClient.command",
        qos: .userInitiated
    )
    private let artworkCacheLimit = 24
    private var artworkCache: [String: Data] = [:]
    private var artworkMisses: Set<String> = []

    func read() async -> Result<MusicReadResult?, AppleMusicClientError> {
        await withCheckedContinuation { continuation in
            readQueue.async {
                continuation.resume(returning: self.readSynchronously())
            }
        }
    }

    func readAfterTrackChange() async -> Result<MusicReadResult?, AppleMusicClientError> {
        await withCheckedContinuation { continuation in
            readQueue.async {
                continuation.resume(returning: self.readAfterTrackChangeSynchronously())
            }
        }
    }

    func send(_ command: AppleMusicCommand) async -> Result<Void, AppleMusicClientError> {
        await withCheckedContinuation { continuation in
            commandQueue.async {
                continuation.resume(
                    returning: self.run(command.script).map { _ in () }
                )
            }
        }
    }

    private func readSynchronously() -> Result<MusicReadResult?, AppleMusicClientError> {
        let result = run(Self.metadataScript)
        guard case .success(let descriptor) = result else {
            return result.map { _ in nil }
        }

        let state = string(at: 1, from: descriptor)
        let title = string(at: 3, from: descriptor)
        guard !title.isEmpty else { return .success(nil) }

        let persistentID = string(at: 2, from: descriptor)
        let artist = string(at: 4, from: descriptor)
        let album = string(at: 5, from: descriptor)
        let trackID = persistentID.isEmpty
            ? "\(title)|\(artist)|\(album)"
            : persistentID

        return .success(
            makeReadResult(
                from: descriptor,
                trackID: trackID,
                state: state,
                artworkData: artworkData(for: trackID)
            )
        )
    }

    private func readAfterTrackChangeSynchronously()
        -> Result<MusicReadResult?, AppleMusicClientError> {
        let result = run(Self.trackChangeMetadataScript)
        guard case .success(let descriptor) = result else {
            return result.map { _ in nil }
        }

        let state = string(at: 1, from: descriptor)
        let title = string(at: 3, from: descriptor)
        guard !title.isEmpty else { return .success(nil) }

        let persistentID = string(at: 2, from: descriptor)
        let artist = string(at: 4, from: descriptor)
        let album = string(at: 5, from: descriptor)
        let trackID = persistentID.isEmpty
            ? "\(title)|\(artist)|\(album)"
            : persistentID
        let embeddedArtwork = descriptor.atIndex(10)?.data
        let resolvedArtwork: Data?

        if let embeddedArtwork, !embeddedArtwork.isEmpty {
            cacheArtwork(embeddedArtwork, for: trackID)
            resolvedArtwork = embeddedArtwork
        } else {
            resolvedArtwork = artworkData(for: trackID)
        }

        return .success(
            makeReadResult(
                from: descriptor,
                trackID: trackID,
                state: state,
                artworkData: resolvedArtwork
            )
        )
    }

    private func makeReadResult(
        from descriptor: NSAppleEventDescriptor,
        trackID: String,
        state: String,
        artworkData: Data?
    ) -> MusicReadResult? {
        let title = string(at: 3, from: descriptor)
        guard !title.isEmpty else { return nil }

        return MusicReadResult(
            trackID: trackID,
            title: title,
            artist: string(at: 4, from: descriptor),
            album: string(at: 5, from: descriptor),
            duration: double(at: 6, from: descriptor),
            position: double(at: 7, from: descriptor),
            isPlaying: state.caseInsensitiveCompare("playing") == .orderedSame,
            volume: min(max(double(at: 8, from: descriptor) / 100, 0), 1),
            isShuffleEnabled: descriptor.atIndex(9)?.booleanValue ?? false,
            artworkData: artworkData
        )
    }

    private func artworkData(for trackID: String) -> Data? {
        if let cached = artworkCache[trackID] {
            return cached
        }
        guard !artworkMisses.contains(trackID) else { return nil }

        guard case .success(let descriptor) = run(Self.artworkScript) else {
            artworkMisses.insert(trackID)
            return nil
        }

        let data = descriptor.data
        guard !data.isEmpty else {
            artworkMisses.insert(trackID)
            return nil
        }

        cacheArtwork(data, for: trackID)
        return data
    }

    private func cacheArtwork(_ data: Data, for trackID: String) {
        if artworkCache.count >= artworkCacheLimit,
           let oldestKey = artworkCache.keys.first {
            artworkCache.removeValue(forKey: oldestKey)
        }
        artworkMisses.remove(trackID)
        artworkCache[trackID] = data
    }

    private func run(_ source: String) -> Result<NSAppleEventDescriptor, AppleMusicClientError> {
        guard let script = NSAppleScript(source: source) else {
            return .failure(.scriptError("无法创建 Apple Music 脚本"))
        }

        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let code = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue
            if code == -1743 || code == -1744 {
                return .failure(.permissionDenied)
            }
            let message = errorInfo[NSAppleScript.errorMessage] as? String
                ?? "无法读取 Apple Music"
            return .failure(.scriptError(message))
        }

        return .success(descriptor)
    }

    private func string(at index: Int, from descriptor: NSAppleEventDescriptor) -> String {
        descriptor.atIndex(index)?.stringValue ?? ""
    }

    private func double(at index: Int, from descriptor: NSAppleEventDescriptor) -> Double {
        descriptor.atIndex(index)?.doubleValue ?? 0
    }

    private static let metadataScript = """
    tell application "Music"
        set stateText to player state as text
        try
            set t to current track
            set trackID to persistent ID of t
            set trackName to name of t
            set trackArtist to artist of t
            set trackAlbum to album of t
            set trackDuration to duration of t
            set trackPosition to player position
            set trackVolume to sound volume
            set shuffleEnabled to shuffle enabled
            return {stateText, trackID, trackName, trackArtist, trackAlbum, trackDuration, trackPosition, trackVolume, shuffleEnabled}
        on error
            return {stateText, "", "", "", "", 0, 0, 0, false}
        end try
    end tell
    """

    private static let artworkScript = """
    tell application "Music"
        try
            set t to current track
            if (count of artworks of t) is 0 then return missing value
            return raw data of artwork 1 of t
        on error
            return missing value
        end try
    end tell
    """

    private static let trackChangeMetadataScript = """
    tell application "Music"
        set stateText to player state as text
        try
            set t to current track
            set trackID to persistent ID of t
            set trackName to name of t
            set trackArtist to artist of t
            set trackAlbum to album of t
            set trackDuration to duration of t
            set trackPosition to player position
            set trackVolume to sound volume
            set shuffleEnabled to shuffle enabled
            set artworkData to missing value
            if (count of artworks of t) > 0 then set artworkData to raw data of artwork 1 of t
            return {stateText, trackID, trackName, trackArtist, trackAlbum, trackDuration, trackPosition, trackVolume, shuffleEnabled, artworkData}
        on error
            return {stateText, "", "", "", "", 0, 0, 0, false, missing value}
        end try
    end tell
    """
}
