import Foundation

struct AppSettings: Codable, Equatable {
    var fitOnOpen = true
    var rememberRecent = true
    var wheelZoom = true
    var doubleClickZoom = true
    var background = "light"
    var slideshowInterval = 5
    var slideshowLoop = true
    var slideshowShuffle = false
    var slideshowTheme = "black"

    static let backgrounds = ["light", "gray", "black"]
    static let themes = ["black", "white", "gradient"]

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppSettings()
        fitOnOpen = try container.decodeIfPresent(Bool.self, forKey: .fitOnOpen) ?? fallback.fitOnOpen
        rememberRecent = try container.decodeIfPresent(Bool.self, forKey: .rememberRecent) ?? fallback.rememberRecent
        wheelZoom = try container.decodeIfPresent(Bool.self, forKey: .wheelZoom) ?? fallback.wheelZoom
        doubleClickZoom = try container.decodeIfPresent(Bool.self, forKey: .doubleClickZoom) ?? fallback.doubleClickZoom
        background = try container.decodeIfPresent(String.self, forKey: .background) ?? fallback.background
        slideshowInterval = try container.decodeIfPresent(Int.self, forKey: .slideshowInterval) ?? fallback.slideshowInterval
        slideshowLoop = try container.decodeIfPresent(Bool.self, forKey: .slideshowLoop) ?? fallback.slideshowLoop
        slideshowShuffle = try container.decodeIfPresent(Bool.self, forKey: .slideshowShuffle) ?? fallback.slideshowShuffle
        slideshowTheme = try container.decodeIfPresent(String.self, forKey: .slideshowTheme) ?? fallback.slideshowTheme
    }

    func validated() -> AppSettings {
        var copy = self
        if !Self.backgrounds.contains(copy.background) { copy.background = "light" }
        if !Self.themes.contains(copy.slideshowTheme) { copy.slideshowTheme = "black" }
        copy.slideshowInterval = min(60, max(1, copy.slideshowInterval))
        return copy
    }
}

final class SettingsStore {
    private let defaults: UserDefaults
    private let settingsKey = "appSettings"
    private let recentKey = "recentFolders"
    private let rotationFile: URL
    private var rotations: [String: Int]

    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImgViewer", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        rotationFile = base.appendingPathComponent("rotations.json")
        if let data = try? Data(contentsOf: rotationFile),
           let stored = try? JSONDecoder().decode([String: Int].self, from: data) {
            rotations = stored
        } else {
            rotations = [:]
        }
    }

    var settings: AppSettings {
        get {
            guard let data = defaults.data(forKey: settingsKey),
                  let stored = try? JSONDecoder().decode(AppSettings.self, from: data) else {
                return AppSettings()
            }
            return stored.validated()
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue.validated()) else { return }
            defaults.set(data, forKey: settingsKey)
        }
    }

    var recentFolders: [String] {
        get { defaults.stringArray(forKey: recentKey) ?? [] }
        set { defaults.set(Array(newValue.prefix(12)), forKey: recentKey) }
    }

    func remember(folder: URL) {
        let path = folder.standardizedFileURL.path
        var list = recentFolders.filter { $0 != path }
        list.insert(path, at: 0)
        recentFolders = list
    }

    func rotation(for url: URL) -> Int {
        rotations[url.standardizedFileURL.path] ?? 0
    }

    var allRotations: [String: Int] { rotations }

    func setRotation(_ degrees: Int, for url: URL) {
        rotations[url.standardizedFileURL.path] = ((degrees % 360) + 360) % 360
        persistRotations()
    }

    func forgetRotation(for url: URL) {
        rotations.removeValue(forKey: url.standardizedFileURL.path)
        persistRotations()
    }

    private func persistRotations() {
        guard let data = try? JSONEncoder().encode(rotations) else { return }
        try? data.write(to: rotationFile, options: .atomic)
    }
}
