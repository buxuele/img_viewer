import Foundation

final class BookmarkStore {
    static let shared = BookmarkStore()

    private let fileURL: URL
    private var bookmarks: [String: Data]

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImgViewer", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("bookmarks.json")
        if let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode([String: Data].self, from: data) {
            bookmarks = stored
        } else {
            bookmarks = [:]
        }
    }

    func save(_ url: URL) {
        guard let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        bookmarks[url.standardizedFileURL.path] = data
        persist()
    }

    func resolve(_ path: String) -> URL? {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard let data = bookmarks[standardized] else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        if stale {
            save(url)
        }
        return url
    }

    func forget(_ path: String) {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        bookmarks.removeValue(forKey: standardized)
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
