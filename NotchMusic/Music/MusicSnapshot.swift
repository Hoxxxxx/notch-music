import AppKit
import Foundation

struct MusicSnapshot {
    let trackID: String
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let position: TimeInterval
    let isPlaying: Bool
    let artwork: NSImage?
    let sampledAt: Date

    func elapsed(at date: Date) -> TimeInterval {
        let base = max(position, 0)
        let value = isPlaying
            ? base + max(0, date.timeIntervalSince(sampledAt))
            : base
        guard duration > 0 else { return value }
        return min(value, duration)
    }

    func updatingPosition(_ position: TimeInterval) -> MusicSnapshot {
        MusicSnapshot(
            trackID: trackID,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            position: min(max(position, 0), duration),
            isPlaying: isPlaying,
            artwork: artwork,
            sampledAt: Date()
        )
    }
}
