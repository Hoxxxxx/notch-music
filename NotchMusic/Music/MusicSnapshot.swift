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

    func progress(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsed(at: date) / duration, 0), 1)
    }
}
