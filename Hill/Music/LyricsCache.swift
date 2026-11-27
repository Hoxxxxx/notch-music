import Foundation

actor LyricsDiskCache {
    static let shared = LyricsDiskCache()

    private struct Entry: Codable {
        let payload: LyricsPayload
        let savedAt: Date
    }

    private static let ttl: TimeInterval = 7 * 24 * 60 * 60
    private static let maxEntries = 200

    private let fileURL: URL?
    private var entries: [String: Entry]?

    init() {
        fileURL = Self.cacheFileURL()
    }

    func payload(for trackID: String) -> LyricsPayload? {
        loadIfNeeded()
        guard let entry = entries?[trackID] else { return nil }
        guard Date().timeIntervalSince(entry.savedAt) < Self.ttl else {
            entries?[trackID] = nil
            write()
            return nil
        }
        return entry.payload
    }

    func store(_ payload: LyricsPayload, for trackID: String) {
        loadIfNeeded()
        entries?[trackID] = Entry(payload: payload, savedAt: Date())
        guard let entries else { return }
        if entries.count > Self.maxEntries {
            let overflow = entries.count - Self.maxEntries
            let staleKeys = entries
                .sorted { $0.value.savedAt < $1.value.savedAt }
                .prefix(overflow)
                .map(\.key)
            for key in staleKeys {
                self.entries?[key] = nil
            }
        }
        write()
    }

    private func loadIfNeeded() {
        guard entries == nil else { return }
        entries = Self.load(from: fileURL)
    }

    private func write() {
        guard let fileURL,
              let entries,
              let data = try? JSONEncoder().encode(entries) else {
            return
        }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL?) -> [String: Entry] {
        guard let url,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(
                  [String: Entry].self,
                  from: data
              ) else {
            return [:]
        }
        let now = Date()
        return decoded.filter {
            now.timeIntervalSince($0.value.savedAt) < ttl
        }
    }

    private static func cacheFileURL() -> URL? {
        guard let base = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else { return nil }

        let directory = base
            .appendingPathComponent(
                Bundle.main.bundleIdentifier ?? "Hill",
                isDirectory: true
            )
            .appendingPathComponent("Lyrics", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            return nil
        }
        return directory.appendingPathComponent("lyrics.json")
    }
}
