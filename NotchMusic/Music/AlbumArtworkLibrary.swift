import AppKit
import Combine

final class AlbumArtworkLibrary: ObservableObject {
    static let shared = AlbumArtworkLibrary()

    @Published private(set) var covers: [NSImage] = []

    private let fetchQueue = DispatchQueue(
        label: "NotchMusic.albumArtwork",
        qos: .utility
    )
    private let coverLimit = 9
    private let refreshInterval: TimeInterval = 60 * 60 * 24 * 7
    private var hasStarted = false
    private var isFetching = false
    private static let lastRefreshKey = "NotchMusic.albumArtwork.lastRefresh"

    func ensureLoaded() {
        guard !hasStarted else { return }
        hasStarted = true

        let cached = Self.loadCachedCovers(limit: coverLimit)
        if !cached.isEmpty {
            covers = cached
        }

        let lastRefresh = UserDefaults.standard.double(
            forKey: Self.lastRefreshKey
        )
        let isStale = Date().timeIntervalSince1970 - lastRefresh
            > refreshInterval
        guard cached.isEmpty || isStale else { return }
        refresh()
    }

    func refresh() {
        guard !isFetching else { return }
        isFetching = true

        fetchQueue.async { [weak self] in
            guard let self else { return }
            let images = Self.fetchCovers(limit: self.coverLimit)

            guard !images.isEmpty else {
                DispatchQueue.main.async {
                    self.isFetching = false
                }
                return
            }

            Self.writeCache(images)
            DispatchQueue.main.async {
                self.covers = images
                self.isFetching = false
                UserDefaults.standard.set(
                    Date().timeIntervalSince1970,
                    forKey: Self.lastRefreshKey
                )
            }
        }
    }

    private static var cacheDirectory: URL? {
        guard let base = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else { return nil }

        let directory = base
            .appendingPathComponent("NotchMusic", isDirectory: true)
            .appendingPathComponent("AlbumArtwork", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private static func loadCachedCovers(limit: Int) -> [NSImage] {
        guard let directory = cacheDirectory,
              let files = try? FileManager.default.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: nil
              ) else { return [] }

        return files
            .filter { $0.pathExtension == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .prefix(limit)
            .compactMap { NSImage(contentsOf: $0) }
    }

    private static func writeCache(_ images: [NSImage]) {
        guard let directory = cacheDirectory else { return }

        for (index, image) in images.enumerated() {
            guard let data = jpegData(for: image) else { continue }
            let url = directory.appendingPathComponent(
                String(format: "cover-%02d.jpg", index)
            )
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func fetchCovers(limit: Int) -> [NSImage] {
        guard !NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.Music"
        ).isEmpty else { return [] }
        guard let script = NSAppleScript(source: libraryScript) else {
            return []
        }

        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        guard errorInfo == nil else { return [] }

        let count = descriptor.numberOfItems
        guard count > 0 else { return [] }

        var images: [NSImage] = []
        for index in 1...count {
            guard let data = descriptor.atIndex(index)?.data,
                  !data.isEmpty,
                  let image = thumbnail(from: data, maxDimension: 320) else {
                continue
            }
            images.append(image)
            if images.count >= limit { break }
        }
        return images
    }

    private static func thumbnail(
        from data: Data,
        maxDimension: CGFloat
    ) -> NSImage? {
        guard let source = NSImage(data: data),
              source.size.width > 0,
              source.size.height > 0 else { return nil }

        let ratio = min(
            1,
            maxDimension / max(source.size.width, source.size.height)
        )
        let size = NSSize(
            width: max(1, (source.size.width * ratio).rounded()),
            height: max(1, (source.size.height * ratio).rounded())
        )

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        source.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        let scaled = NSImage(size: size)
        scaled.addRepresentation(rep)
        return softened(scaled, radius: 4)
    }

    private static func softened(_ image: NSImage, radius: CGFloat) -> NSImage {
        guard let tiff = image.tiffRepresentation,
              let input = CIImage(data: tiff),
              let filter = CIFilter(name: "CIGaussianBlur") else {
            return image
        }

        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: input.extent) else {
            return image
        }

        let result = NSImage(size: image.size)
        result.addRepresentation(NSCIImageRep(ciImage: output))
        return result
    }

    private static func jpegData(for image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.86]
        )
    }

    private static let libraryScript = """
    tell application "Music"
        set found to {}
        set seenAlbums to {}
        try
            set libraryPlaylist to library playlist 1
            set trackCount to (count of tracks of libraryPlaylist)
        on error
            return {}
        end try
        if trackCount is 0 then return {}
        set step to 1
        if trackCount > 400 then set step to (trackCount div 400)
        set trackIndex to 1
        repeat while ((count of found) < 9) and (trackIndex is less than or equal to trackCount)
            try
                set t to track trackIndex of libraryPlaylist
                set albumName to album of t
                if albumName is not missing value and albumName is not "" then
                    if seenAlbums does not contain albumName then
                        if (count of artworks of t) > 0 then
                            set end of seenAlbums to albumName
                            set end of found to (raw data of artwork 1 of t)
                        end if
                    end if
                end if
            end try
            set trackIndex to (trackIndex + step)
        end repeat
        return found
    end tell
    """
}
