import AppKit
import ImageIO
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Cards are a few hundred points wide, so a full-size screenshot would only
/// cost memory; previews are decoded no larger than this on their longest side.
private let maxPreviewPixels = 1024

/// What a card would otherwise read from disk on every render: the picture for
/// image clips and image files, and the Finder icon for other file clips.
/// Lookups are synchronous and never touch disk; loading runs off the main
/// actor and fills caches bounded by count and byte cost.
@MainActor
enum ClipPreviewProvider {
    struct FileInfo {
        let icon: NSImage
        let isMissing: Bool
    }

    private static let images: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 200
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    private static let icons: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 256
        return cache
    }()

    /// The one file a `.file` clip points at when that file is an image. Decided
    /// from the path extension so it is safe to ask on every render.
    static func imageFileURL(for item: ClipItem) -> URL? {
        guard item.type == .file,
              item.fileURLs.count == 1,
              let url = item.fileURLs.first.flatMap(URL.init(string:)),
              url.isFileURL,
              let type = UTType(filenameExtension: url.pathExtension),
              type.conforms(to: .image) else { return nil }
        return url
    }

    static func showsImage(_ item: ClipItem) -> Bool {
        item.type == .image || imageFileURL(for: item) != nil
    }

    static func cachedImage(for item: ClipItem) -> NSImage? {
        guard let key = imageKey(for: item) else { return nil }
        return images.object(forKey: key)
    }

    static func image(for item: ClipItem, scale: CGFloat) async -> NSImage? {
        guard let key = imageKey(for: item) else { return nil }
        if let cached = images.object(forKey: key) { return cached }
        let loaded: NSImage?
        if item.type == .image, let url = ClipboardStore.shared.imageURL(for: item) {
            loaded = await downsampled(url)
        } else if let url = imageFileURL(for: item) {
            loaded = await thumbnail(for: url, scale: scale)
        } else {
            loaded = nil
        }
        guard let loaded else { return nil }
        images.setObject(loaded, forKey: key, cost: cost(of: loaded))
        return loaded
    }

    static func cachedIcon(for item: ClipItem) -> NSImage? {
        guard let url = firstFileURL(for: item) else { return nil }
        return icons.object(forKey: url.path as NSString)
    }

    /// The file's own Finder icon when it is there, and its type's icon when it
    /// is not: the workspace hands back a blank page for a path that no longer
    /// exists. A file counts as missing only on ENOENT, and never in the
    /// sandboxed build, where access to a copied file does not survive a
    /// relaunch and the stat fails for files that are still there.
    static func fileInfo(for item: ClipItem) async -> FileInfo? {
        guard let url = firstFileURL(for: item) else { return nil }
        let path = url.path
        let status = await Task.detached(priority: .userInitiated) { Self.fileStatus(path) }.value
        guard status == .present else {
            let icon = NSWorkspace.shared.icon(for: UTType(filenameExtension: url.pathExtension) ?? .data)
            return FileInfo(icon: icon, isMissing: status == .missing && !ClipboardStore.isSandboxed)
        }
        let key = path as NSString
        if let cached = icons.object(forKey: key) { return FileInfo(icon: cached, isMissing: false) }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icons.setObject(icon, forKey: key)
        return FileInfo(icon: icon, isMissing: false)
    }

    private static func imageKey(for item: ClipItem) -> NSString? {
        if item.type == .image {
            guard let path = ClipboardStore.shared.imageURL(for: item)?.path else { return nil }
            return "\(path)|\(item.imageHash ?? "")" as NSString
        }
        return imageFileURL(for: item)?.path as NSString?
    }

    private static func firstFileURL(for item: ClipItem) -> URL? {
        guard item.type == .file,
              let url = item.fileURLs.first.flatMap(URL.init(string:)),
              url.isFileURL else { return nil }
        return url
    }

    private static func downsampled(_ url: URL) async -> NSImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.decode(url))
            }
        }
    }

    private static func thumbnail(for url: URL, scale: CGFloat) async -> NSImage? {
        let side = CGFloat(maxPreviewPixels) / scale
        let request = QLThumbnailGenerator.Request(fileAt: url,
                                                   size: CGSize(width: side, height: side),
                                                   scale: scale,
                                                   representationTypes: .thumbnail)
        let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        return representation?.nsImage
    }

    private static func cost(of image: NSImage) -> Int {
        let rep = image.representations.first
        let width = rep?.pixelsWide ?? Int(image.size.width)
        let height = rep?.pixelsHigh ?? Int(image.size.height)
        return width * height * 4
    }

    private enum FileStatus {
        case present
        case missing
        case unknown
    }

    nonisolated private static func fileStatus(_ path: String) -> FileStatus {
        var info = stat()
        if stat(path, &info) == 0 { return .present }
        return errno == ENOENT ? .missing : .unknown
    }

    nonisolated private static func decode(_ url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPreviewPixels
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
