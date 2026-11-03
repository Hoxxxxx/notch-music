import AppKit
import CoreImage
import Foundation

struct MusicSnapshot {
    let trackID: String
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let position: TimeInterval
    let isPlaying: Bool
    let volume: Double
    let isShuffleEnabled: Bool
    let artwork: NSImage?
    let sampledAt: Date

    var accentColor: NSColor {
        ArtworkPalette.color(trackID: trackID, artwork: artwork)
    }

    var bottomBackgroundColor: NSColor {
        ArtworkPalette.bottomColor(trackID: trackID, artwork: artwork)
    }

    func elapsed(at date: Date) -> TimeInterval {
        let base = max(position, 0)
        let value = isPlaying
            ? base + max(0, date.timeIntervalSince(sampledAt))
            : base
        guard duration > 0 else { return value }
        return min(value, duration)
    }

    func updating(
        position: TimeInterval? = nil,
        volume: Double? = nil,
        isPlaying: Bool? = nil,
        isShuffleEnabled: Bool? = nil
    ) -> MusicSnapshot {
        MusicSnapshot(
            trackID: trackID,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            position: min(max(position ?? self.position, 0), duration),
            isPlaying: isPlaying ?? self.isPlaying,
            volume: min(max(volume ?? self.volume, 0), 1),
            isShuffleEnabled: isShuffleEnabled ?? self.isShuffleEnabled,
            artwork: artwork,
            sampledAt: Date()
        )
    }
}

enum ArtworkPalette {
    static let fallback = NSColor(
        srgbRed: 1.0,
        green: 0.38,
        blue: 0.30,
        alpha: 1
    )
    private static let lightBottomFallback = NSColor(
        srgbRed: 0.84,
        green: 0.84,
        blue: 0.86,
        alpha: 1
    )

    private static let cache = NSCache<NSString, NSColor>()
    private static let bottomCache = NSCache<NSString, NSColor>()
    private static let context = CIContext()

    static func color(trackID: String, artwork: NSImage?) -> NSColor {
        if let cached = cache.object(forKey: trackID as NSString) {
            return cached
        }

        let color = artwork.flatMap(sampledColor) ?? fallback
        cache.setObject(color, forKey: trackID as NSString)
        return color
    }

    static func bottomColor(trackID: String, artwork: NSImage?) -> NSColor {
        if let cached = bottomCache.object(forKey: trackID as NSString) {
            return cached
        }

        let sampledColor = artwork.flatMap(sampledBottomColor)
        let color = sampledColor.map { color in
            guard let rgb = color.usingColorSpace(.deviceRGB) else {
                return color
            }
            let luminance = 0.2126 * rgb.redComponent
                + 0.7152 * rgb.greenComponent
                + 0.0722 * rgb.blueComponent
            guard luminance < 0.22, let artwork else { return color }
            return sampledHighContrastColor(from: artwork) ?? lightBottomFallback
        } ?? fallback
        bottomCache.setObject(color, forKey: trackID as NSString)
        return color
    }

    private static func sampledColor(from image: NSImage) -> NSColor? {
        guard let rgb = averageColor(
            from: image,
            normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1)
        ) else {
            return nil
        }

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        rgb.getHue(
            &hue,
            saturation: &saturation,
            brightness: &brightness,
            alpha: &alpha
        )

        guard saturation > 0.08 else { return nil }

        return NSColor(
            hue: hue,
            saturation: min(max(saturation * 1.4, 0.52), 0.88),
            brightness: min(max(brightness, 0.72), 0.94),
            alpha: 1
        )
    }

    private static func sampledBottomColor(from image: NSImage) -> NSColor? {
        averageColor(
            from: image,
            normalizedRect: CGRect(x: 0.08, y: 0.02, width: 0.84, height: 0.30)
        )
    }

    private static func sampledHighContrastColor(from image: NSImage) -> NSColor? {
        guard let cgImage = image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else {
            return nil
        }

        let input = CIImage(cgImage: cgImage)
        let extent = input.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        let sampleSize = 48
        let scaled = input.transformed(
            by: CGAffineTransform(
                scaleX: CGFloat(sampleSize) / extent.width,
                y: CGFloat(sampleSize) / extent.height
            )
        )
        let bounds = CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize)
        var pixels = [UInt8](
            repeating: 0,
            count: sampleSize * sampleSize * 4
        )
        pixels.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            context.render(
                scaled,
                toBitmap: baseAddress,
                rowBytes: sampleSize * 4,
                bounds: bounds,
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
        }

        var bestScore: CGFloat = 0
        var bestColor: NSColor?

        for offset in stride(from: 0, to: pixels.count, by: 4) {
            guard pixels[offset + 3] > 0 else { continue }

            let red = CGFloat(pixels[offset]) / 255
            let green = CGFloat(pixels[offset + 1]) / 255
            let blue = CGFloat(pixels[offset + 2]) / 255
            let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            guard luminance > 0.22 else { continue }

            let saturation = (max(red, green, blue) - min(red, green, blue))
                / max(red, green, blue)
            let score = luminance * (0.25 + saturation * 0.75)
            guard score > bestScore else { continue }

            bestScore = score
            bestColor = NSColor(
                srgbRed: red,
                green: green,
                blue: blue,
                alpha: 1
            )
        }

        return bestColor
    }

    private static func averageColor(
        from image: NSImage,
        normalizedRect: CGRect
    ) -> NSColor? {
        guard let cgImage = image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else {
            return nil
        }

        let input = CIImage(cgImage: cgImage)
        let extent = input.extent
        let sampleRect = CGRect(
            x: extent.minX + extent.width * normalizedRect.minX,
            y: extent.minY + extent.height * normalizedRect.minY,
            width: extent.width * normalizedRect.width,
            height: extent.height * normalizedRect.height
        )
        guard let filter = CIFilter(
            name: "CIAreaAverage",
            parameters: [
                kCIInputImageKey: input,
                kCIInputExtentKey: CIVector(cgRect: sampleRect)
            ]
        ), let output = filter.outputImage else {
            return nil
        }

        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            context.render(
                output,
                toBitmap: baseAddress,
                rowBytes: 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
        }

        let rawColor = NSColor(
            srgbRed: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
        return rawColor.usingColorSpace(.deviceRGB)
    }
}
