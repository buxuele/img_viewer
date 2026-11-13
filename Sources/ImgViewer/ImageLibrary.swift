import Foundation

struct ImageItem: Identifiable, Equatable {
    let url: URL
    var rotation: Int = 0

    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

enum ImageLibrary {
    static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "jfif", "png", "gif", "bmp", "webp",
        "tif", "tiff", "heic", "heif", "avif", "ico",
    ]

    static func isImage(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func naturalCompare(_ left: String, _ right: String) -> Bool {
        left.localizedStandardCompare(right) == .orderedAscending
    }

    static func scan(folder: URL, rotations: [String: Int]) throws -> [ImageItem] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        let entries = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )
        var items: [ImageItem] = []
        for entry in entries {
            guard let values = try? entry.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  isImage(entry) else { continue }
            let resolved = entry.resolvingSymlinksInPath().standardizedFileURL
            items.append(ImageItem(url: resolved, rotation: rotations[resolved.path] ?? 0))
        }
        items.sort { naturalCompare($0.name, $1.name) }
        return items
    }
}
