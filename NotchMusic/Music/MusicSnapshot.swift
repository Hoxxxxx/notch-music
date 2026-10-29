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
    let artwork: NSImage?
    let sampledAt: Date

    var accentColor: NSColor {
        ArtworkPalette.color(trackID: trackID, artwork: artwork)
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
        volume: Double? = nil
    ) -> MusicSnapshot {
        MusicSnapshot(
            trackID: trackID,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            position: min(max(position ?? self.position, 0), duration),
            isPlaying: isPlaying,
            volume: min(max(volume ?? self.volume, 0), 1),
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

    private static let cache = NSCache<NSString, NSColor>()
    private static let context = CIContext()

    static func color(trackID: String, artwork: NSImage?) -> NSColor {
        if let cached = cache.object(forKey: trackID as NSString) {
            return cached
        }

        let color = artwork.flatMap(sampledColor) ?? fallback
        cache.setObject(color, forKey: trackID as NSString)
        return color
    }

    private static func sampledColor(from image: NSImage) -> NSColor? {
        guard let cgImage = image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else {
            return nil
        }

        let input = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(
            name: "CIAreaAverage",
            parameters: [
                kCIInputImageKey: input,
                kCIInputExtentKey: CIVector(cgRect: input.extent)
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
        guard let rgb = rawColor.usingColorSpace(.deviceRGB) else {
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
}
