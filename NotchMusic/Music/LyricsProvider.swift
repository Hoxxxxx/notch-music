import Combine
import Foundation

struct LyricLine: Identifiable, Equatable, Sendable {
    let id: Int
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}

struct SyncedLyrics: Equatable, Sendable {
    let lines: [LyricLine]

    func activeIndex(at position: TimeInterval) -> Int? {
        guard let first = lines.first else { return nil }
        guard position >= first.start else { return nil }

        var low = 0
        var high = lines.count - 1
        var result = 0
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].start <= position {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    func progress(for index: Int, at position: TimeInterval) -> Double {
        guard lines.indices.contains(index) else { return 0 }
        let line = lines[index]
        guard line.end > line.start else { return 1 }
        return min(
            max((position - line.start) / (line.end - line.start), 0),
            1
        )
    }
}

enum LyricsPayload: Sendable {
    case synced(SyncedLyrics)
    case plain(String)
    case instrumental
    case empty
}

struct LyricsQuery: Sendable {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
}

struct LRCLIBTrack: Decodable, Sendable {
    let id: Int
    let trackName: String
    let artistName: String
    let albumName: String?
    let duration: TimeInterval
    let instrumental: Bool
    let plainLyrics: String?
    let syncedLyrics: String?
    let lyricsfile: String?
}

enum LyricsError: Error, Sendable {
    case network
    case rateLimited
    case server
    case invalidResponse
}

struct LyricsProvider: Sendable {
    private static let userAgent =
        "NotchMusic/0.4.2 (https://github.com/Hoxxxxx/notch-music)"
    private static let requestTimeout: TimeInterval = 30
    private static let maxAttempts = 3
    private static let maxRetryDelay: TimeInterval = 10

    func fetch(_ query: LyricsQuery) async throws -> LyricsPayload {
        let (tracks, reachedServer) = await candidates(for: query)
        guard reachedServer else { throw LyricsError.network }
        guard let track = bestMatch(
            in: tracks,
            query: query
        ) else {
            return .empty
        }
        return payload(for: track, query: query)
    }

    private func candidates(
        for query: LyricsQuery
    ) async -> ([LRCLIBTrack], Bool) {
        var tracks: [LRCLIBTrack] = []
        var reachedServer = false

        await withTaskGroup(of: [LRCLIBTrack]?.self) { group in
            group.addTask {
                try? await exactMatch(query)
            }
            group.addTask {
                try? await search(query)
            }

            for await result in group {
                guard let result else { continue }
                reachedServer = true
                guard !result.isEmpty else { continue }
                tracks = result
                group.cancelAll()
                break
            }
        }
        return (tracks, reachedServer)
    }

    private func payload(
        for track: LRCLIBTrack,
        query: LyricsQuery
    ) -> LyricsPayload {
        if track.instrumental {
            return .instrumental
        }

        if let lyricsfile = track.lyricsfile,
           let lyrics = LyricsParser.parse(
               lyricsfile: lyricsfile,
               duration: query.duration
           ) {
            return .synced(simplifiedChinese(lyrics))
        }

        if let synced = track.syncedLyrics,
           let lyrics = LyricsParser.parse(
               lrc: synced,
               duration: query.duration
           ) {
            return .synced(simplifiedChinese(lyrics))
        }

        if let plain = track.plainLyrics,
           !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .plain(simplifiedChinese(plain))
        }

        return .empty
    }

    private static let simplifiedChineseTransform =
        StringTransform(rawValue: "Traditional-Simplified")

    private func simplifiedChinese(_ text: String) -> String {
        text.applyingTransform(
            Self.simplifiedChineseTransform,
            reverse: false
        ) ?? text
    }

    private func simplifiedChinese(_ lyrics: SyncedLyrics) -> SyncedLyrics {
        SyncedLyrics(
            lines: lyrics.lines.map { line in
                LyricLine(
                    id: line.id,
                    start: line.start,
                    end: line.end,
                    text: simplifiedChinese(line.text)
                )
            }
        )
    }

    private func exactMatch(
        _ query: LyricsQuery
    ) async throws -> [LRCLIBTrack] {
        guard !query.artist.isEmpty,
              (1...3600).contains(query.duration) else {
            return []
        }

        var items = [
            URLQueryItem(name: "track_name", value: query.title),
            URLQueryItem(name: "artist_name", value: query.artist)
        ]
        if !query.album.isEmpty {
            items.append(
                URLQueryItem(name: "album_name", value: query.album)
            )
        }
        items.append(
            URLQueryItem(
                name: "duration",
                value: String(Int(query.duration.rounded()))
            )
        )

        var components = URLComponents(
            string: "https://lrclib.net/api/get"
        )
        components?.queryItems = items
        guard let url = components?.url else { return [] }

        let (data, status) = try await fetchData(url: url)
        guard status == 200 else { return [] }
        return [try JSONDecoder().decode(LRCLIBTrack.self, from: data)]
    }

    private func search(
        _ query: LyricsQuery
    ) async throws -> [LRCLIBTrack] {
        var items = [
            URLQueryItem(name: "track_name", value: query.title)
        ]
        if !query.artist.isEmpty {
            items.append(
                URLQueryItem(name: "artist_name", value: query.artist)
            )
        }
        let requestItems = items

        guard Self.containsCJK(query.title) else {
            let tracks = try await search(requestItems)
            guard tracks.isEmpty, !query.artist.isEmpty else {
                return tracks
            }
            return try await search([
                URLQueryItem(name: "track_name", value: query.title)
            ], timeout: Self.requestTimeout * 0.6)
        }

        async let structured = try? search(requestItems)
        async let keyword = try? search([
            URLQueryItem(name: "q", value: query.title)
        ])
        let (structuredTracks, keywordTracks) = await (structured, keyword)

        switch (structuredTracks, keywordTracks) {
        case let (structured?, keyword?):
            var seen = Set<Int>()
            return (structured + keyword).filter {
                seen.insert($0.id).inserted
            }
        case let (structured?, nil):
            return structured
        case let (nil, keyword?):
            return keyword
        case (nil, nil):
            throw LyricsError.network
        }
    }

    private func search(
        _ items: [URLQueryItem],
        timeout: TimeInterval = requestTimeout
    ) async throws -> [LRCLIBTrack] {
        var components = URLComponents(
            string: "https://lrclib.net/api/search"
        )
        components?.queryItems = items
        guard let url = components?.url else { return [] }

        let (data, status) = try await fetchData(url: url, timeout: timeout)
        guard status == 200 else { return [] }
        return try JSONDecoder().decode([LRCLIBTrack].self, from: data)
    }

    private func fetchData(
        url: URL,
        timeout: TimeInterval = requestTimeout
    ) async throws -> (Data, Int) {
        var attempt = 0

        while true {
            attempt += 1
            var request = URLRequest(url: url)
            request.timeoutInterval = timeout
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue(
                Self.userAgent,
                forHTTPHeaderField: "User-Agent"
            )

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(
                    for: request
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError {
                if error.code == .cancelled {
                    throw CancellationError()
                }
                if error.code != .timedOut, attempt < 2 {
                    try await Task.sleep(for: .seconds(0.6))
                    continue
                }
                throw LyricsError.network
            }

            guard let http = response as? HTTPURLResponse else {
                throw LyricsError.invalidResponse
            }

            switch http.statusCode {
            case 200..<300:
                return (data, http.statusCode)
            case 429, 500, 502, 503, 504:
                let delay = Self.retryDelay(for: http, attempt: attempt)
                guard attempt < Self.maxAttempts,
                      delay <= Self.maxRetryDelay else {
                    throw http.statusCode == 429
                        ? LyricsError.rateLimited
                        : LyricsError.server
                }
                try await Task.sleep(for: .seconds(delay))
            default:
                return (data, http.statusCode)
            }
        }
    }

    private static func retryDelay(
        for response: HTTPURLResponse,
        attempt: Int
    ) -> TimeInterval {
        let base: TimeInterval
        if let raw = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = Double(raw),
           seconds >= 0 {
            base = seconds
        } else {
            base = min(4, pow(2, Double(attempt - 1)))
        }
        return base + Double.random(in: 0...(base * 0.3))
    }

    private func bestMatch(
        in tracks: [LRCLIBTrack],
        query: LyricsQuery
    ) -> LRCLIBTrack? {
        let title = Self.normalized(query.title)
        let artist = Self.normalized(query.artist)
        let expectsCJK = Self.containsCJK(query.title)

        func score(_ track: LRCLIBTrack) -> Double {
            var value = abs(track.duration - query.duration)
            if value > 6 {
                value += 10
            }

            if Self.normalized(track.trackName) != title {
                value += 4
            }

            let trackArtist = Self.normalized(track.artistName)
            if !artist.isEmpty,
               !trackArtist.isEmpty,
               !trackArtist.contains(artist),
               !artist.contains(trackArtist) {
                value += 3
            }

            if track.instrumental {
                value += 20
            }

            let lyricText = [track.syncedLyrics, track.plainLyrics]
                .compactMap { $0 }
                .joined()
            if expectsCJK, !Self.containsCJK(lyricText) {
                value += 8
            }

            if track.syncedLyrics?.isEmpty == false
                || track.lyricsfile?.isEmpty == false {
                value -= 2
            }
            return value
        }

        return tracks.min {
            score($0) < score($1)
        }
    }

    private static func normalized(_ value: String) -> String {
        let converted = value.applyingTransform(
            simplifiedChineseTransform,
            reverse: false
        ) ?? value
        return converted
            .folding(
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive,
                    .widthInsensitive
                ],
                locale: .current
            )
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsCJK(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF,
                 0x4E00...0x9FFF,
                 0xF900...0xFAFF:
                return true
            default:
                return false
            }
        }
    }
}

enum LyricsParser {
    static func parse(
        lyricsfile: String,
        duration: TimeInterval
    ) -> SyncedLyrics? {
        struct Builder {
            var text = ""
            var start: TimeInterval?
            var end: TimeInterval?
        }

        var builders: [Builder] = []
        var current: Builder?
        var inWords = false

        func flush() {
            guard let builder = current,
                  builder.start != nil,
                  !builder.text.isEmpty else {
                current = nil
                return
            }
            builders.append(builder)
            current = nil
        }

        for rawLine in lyricsfile.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let isIndented = rawLine.first == " "
                || rawLine.first == "\t"

            if trimmed.hasPrefix("- text:") {
                guard !(inWords && isIndented) else { continue }
                flush()
                let text = String(
                    trimmed.dropFirst("- text:".count)
                )
                current = Builder(
                    text: unquote(text.trimmingCharacters(
                        in: .whitespaces
                    ))
                )
                inWords = false
            } else if trimmed == "words:" {
                inWords = true
            } else if trimmed.hasPrefix("start_ms:") {
                guard !inWords else { continue }
                current?.start = milliseconds(after: "start_ms:", in: trimmed)
            } else if trimmed.hasPrefix("end_ms:") {
                guard !inWords else { continue }
                current?.end = milliseconds(after: "end_ms:", in: trimmed)
            }
        }
        flush()

        return buildLines(
            from: builders.map {
                (text: $0.text, start: $0.start, end: $0.end)
            },
            duration: duration
        )
    }

    static func parse(
        lrc: String,
        duration: TimeInterval
    ) -> SyncedLyrics? {
        let expression = try? NSRegularExpression(
            pattern: #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#
        )
        guard let expression else { return nil }

        var entries: [(start: TimeInterval, text: String)] = []

        for rawLine in lrc.components(separatedBy: .newlines) {
            let line = rawLine as NSString
            let matches = expression.matches(
                in: rawLine,
                range: NSRange(location: 0, length: line.length)
            )
            guard !matches.isEmpty else { continue }

            var text = expression.stringByReplacingMatches(
                in: rawLine,
                range: NSRange(location: 0, length: line.length),
                withTemplate: ""
            )
            text = text.replacingOccurrences(
                of: #"<\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?>"#,
                with: "",
                options: .regularExpression
            )
            text = text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }

            for match in matches {
                let minutes = Int(line.substring(
                    with: match.range(at: 1)
                )) ?? 0
                let seconds = Int(line.substring(
                    with: match.range(at: 2)
                )) ?? 0
                var fraction: Double = 0
                if match.range(at: 3).location != NSNotFound {
                    let raw = line.substring(with: match.range(at: 3))
                    fraction = (Double(raw) ?? 0)
                        / pow(10, Double(raw.count))
                }
                entries.append((
                    TimeInterval(minutes * 60 + seconds) + fraction,
                    text
                ))
            }
        }

        guard !entries.isEmpty else { return nil }
        entries.sort { $0.start < $1.start }

        var lines: [LyricLine] = []
        for (index, entry) in entries.enumerated() {
            let next = entries.dropFirst(index + 1).first?.start
            let end = estimatedEnd(
                start: entry.start,
                next: next,
                text: entry.text,
                duration: duration
            )
            lines.append(
                LyricLine(
                    id: index,
                    start: entry.start,
                    end: end,
                    text: entry.text
                )
            )
        }
        return SyncedLyrics(lines: lines)
    }

    private static func buildLines(
        from builders: [(text: String, start: TimeInterval?, end: TimeInterval?)],
        duration: TimeInterval
    ) -> SyncedLyrics? {
        let timed = builders.filter { $0.start != nil }
        guard !timed.isEmpty else { return nil }

        var lines: [LyricLine] = []
        for (index, builder) in timed.enumerated() {
            guard let start = builder.start else { continue }
            let next = timed.dropFirst(index + 1).first?.start
            var end = builder.end ?? next
                ?? estimatedEnd(
                    start: start,
                    next: nil,
                    text: builder.text,
                    duration: duration
                )
            if let next, next > start {
                end = min(end, next)
            }
            end = max(end, start + 0.4)
            if duration > start {
                end = min(end, duration)
            }
            lines.append(
                LyricLine(
                    id: index,
                    start: start,
                    end: end,
                    text: builder.text
                )
            )
        }
        return lines.isEmpty ? nil : SyncedLyrics(lines: lines)
    }

    private static func estimatedEnd(
        start: TimeInterval,
        next: TimeInterval?,
        text: String,
        duration: TimeInterval
    ) -> TimeInterval {
        let estimate = start + max(
            2.5,
            min(8, Double(text.count) * 0.35)
        )
        let limit = next.map { min($0, estimate) } ?? min(estimate, duration)
        return max(limit, start + 0.4)
    }

    private static func milliseconds(
        after prefix: String,
        in line: String
    ) -> TimeInterval? {
        let value = line.dropFirst(prefix.count)
            .trimmingCharacters(in: .whitespaces)
        guard let milliseconds = Double(value) else { return nil }
        return milliseconds / 1000
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2,
              let first = value.first,
              let last = value.last,
              (first == "\"" && last == "\"")
                || (first == "'" && last == "'") else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }
}

@MainActor
final class LyricsController: ObservableObject {
    enum State {
        case idle
        case loading(trackID: String)
        case synced(trackID: String, lyrics: SyncedLyrics)
        case plain(trackID: String, text: String)
        case instrumental(trackID: String)
        case unavailable(trackID: String)
        case failed(trackID: String)
    }

    @Published private(set) var state: State = .idle

    private let provider = LyricsProvider()
    private var cache: [String: LyricsPayload] = [:]
    private var task: Task<Void, Never>?
    private var currentTrackID: String?

    func load(for snapshot: MusicSnapshot) {
        guard currentTrackID != snapshot.trackID else { return }
        fetch(snapshot)
    }

    func retry(for snapshot: MusicSnapshot) {
        fetch(snapshot)
    }

    private func fetch(_ snapshot: MusicSnapshot) {
        currentTrackID = snapshot.trackID
        task?.cancel()

        if let cached = cache[snapshot.trackID] {
            state = state(for: cached, trackID: snapshot.trackID)
            return
        }

        let trackID = snapshot.trackID
        let title = snapshot.title
        let artist = snapshot.artist
        let album = snapshot.album
        let duration = snapshot.duration
        state = .loading(trackID: trackID)

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let payload = try await provider.fetch(
                    LyricsQuery(
                        title: title,
                        artist: artist,
                        album: album,
                        duration: duration
                    )
                )
                guard !Task.isCancelled,
                      self.currentTrackID == trackID else {
                    return
                }
                if case .empty = payload {
                    self.cache.removeValue(forKey: trackID)
                } else {
                    self.cache[trackID] = payload
                }
                self.state = self.state(for: payload, trackID: trackID)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled,
                      self.currentTrackID == trackID else {
                    return
                }
                self.state = .failed(trackID: trackID)
            }
        }
    }

    func clear() {
        task?.cancel()
        task = nil
        currentTrackID = nil
        state = .idle
    }

    private func state(
        for payload: LyricsPayload,
        trackID: String
    ) -> State {
        switch payload {
        case .synced(let lyrics):
            return .synced(trackID: trackID, lyrics: lyrics)
        case .plain(let text):
            return .plain(trackID: trackID, text: text)
        case .instrumental:
            return .instrumental(trackID: trackID)
        case .empty:
            return .unavailable(trackID: trackID)
        }
    }
}
