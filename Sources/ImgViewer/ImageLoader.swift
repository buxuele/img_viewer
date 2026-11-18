import AppKit
import ImageIO

struct LoadedImage {
    let image: NSImage
    let pixelSize: CGSize
}

final class ImageLoader {
    static let shared = ImageLoader()

    private let cache = NSCache<NSString, NSImage>()
    private let queue = DispatchQueue(label: "imgviewer.loader", qos: .userInitiated, attributes: .concurrent)

    init() {
        cache.totalCostLimit = 512 * 1024 * 1024
    }

    func load(url: URL, maxPixel: Int, completion: @escaping (LoadedImage?) -> Void) {
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? 0
        let key = "\(url.path)|\(modified)|\(maxPixel)" as NSString
        if let cached = cache.object(forKey: key) {
            DispatchQueue.main.async {
                completion(LoadedImage(image: cached, pixelSize: cached.size))
            }
            return
        }
        queue.async {
            let loaded = Self.decode(url: url, maxPixel: maxPixel)
            if let loaded {
                let cost = Int(loaded.pixelSize.width * loaded.pixelSize.height * 4)
                self.cache.setObject(loaded.image, forKey: key, cost: cost)
            }
            DispatchQueue.main.async {
                completion(loaded)
            }
        }
    }

    private static func decode(url: URL, maxPixel: Int) -> LoadedImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let cgImage: CGImage?
        if maxPixel > 0 {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            ]
            cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
                ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
        } else {
            var fullSize = 0
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
                let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
                let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
                fullSize = max(width, height)
            }
            if fullSize > 0 {
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: fullSize,
                ]
                cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
                    ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
            } else {
                cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
            }
        }
        guard let cgImage else { return nil }
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let image = NSImage(cgImage: cgImage, size: size)
        return LoadedImage(image: image, pixelSize: size)
    }
}
