import AppKit
import JavaScriptCore

enum MultiAvatarSettings {
    static let seedKey = "NotchMusic.multiavatarSeed"
    static let defaultSeed = "Hoxxxxx"
}

enum MultiAvatarRenderer {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 32
        return cache
    }()
    private static let context: JSContext? = {
        guard let url = Bundle.main.url(
            forResource: "multiavatar.min",
            withExtension: "js"
        ),
        let source = try? String(contentsOf: url, encoding: .utf8),
        let context = JSContext() else {
            return nil
        }

        context.evaluateScript(source)
        return context.exception == nil ? context : nil
    }()
    private static let lock = NSLock()

    static func image(for seed: String) -> NSImage? {
        let value = seed.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSeed = value.isEmpty
            ? MultiAvatarSettings.defaultSeed
            : value

        lock.lock()
        defer { lock.unlock() }

        let cacheKey = resolvedSeed as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        guard let context,
              let function = context.objectForKeyedSubscript("multiavatar"),
              let svg = function.call(withArguments: [resolvedSeed])?.toString(),
              let image = NSImage(data: Data(svg.utf8)) else {
            return nil
        }

        cache.setObject(image, forKey: cacheKey)
        return image
    }
}
