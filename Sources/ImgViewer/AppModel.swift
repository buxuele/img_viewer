import AppKit
import Combine
import ImageIO

struct ImageProperties {
    let name: String
    let path: String
    let format: String
    let width: Int?
    let height: Int?
    let bytes: Int64?
    let modified: Date?
    let rotation: Int
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var images: [ImageItem] = []
    @Published private(set) var index = 0
    @Published private(set) var folder: URL?
    @Published private(set) var recent: [URL] = []
    @Published var settings: AppSettings
    @Published var showingOptions = false
    @Published var showingProperties = false
    @Published var properties: ImageProperties?
    @Published var alertMessage: String?
    @Published var slideshowImage: NSImage?
    @Published var isSlideshowRunning = false

    let canvas = CanvasState()
    let store: SettingsStore
    private var loadToken = 0

    init(store: SettingsStore = SettingsStore()) {
        self.store = store
        settings = store.settings
        refreshRecent()
    }

    var current: ImageItem? {
        images.indices.contains(index) ? images[index] : nil
    }

    var hasImages: Bool { !images.isEmpty }

    var windowTitle: String {
        guard let current else { return "照片查看器" }
        return "\(current.name) - 照片查看器"
    }

    var counterText: String {
        guard hasImages else { return "" }
        return "第 \(index + 1) 张 / 共 \(images.count) 张"
    }

    var folderName: String {
        folder?.lastPathComponent ?? "未打开文件夹"
    }

    var canGoPrevious: Bool { index > 0 }
    var canGoNext: Bool { index + 1 < images.count }

    var menuEntries: [CanvasMenuEntry] {
        [
            CanvasMenuEntry(key: "open-folder", title: "打开文件夹…"),
            CanvasMenuEntry(key: "-", title: ""),
            CanvasMenuEntry(key: "copy", title: "复制", enabled: hasImages),
            CanvasMenuEntry(key: "copy-path", title: "复制文件路径", enabled: hasImages),
            CanvasMenuEntry(key: "reveal", title: "在访达中显示", enabled: hasImages),
            CanvasMenuEntry(key: "save-as", title: "另存为…", enabled: hasImages),
            CanvasMenuEntry(key: "-", title: ""),
            CanvasMenuEntry(key: "wallpaper", title: "设为桌面背景", enabled: hasImages),
            CanvasMenuEntry(key: "rotate-left", title: "逆时针旋转", enabled: hasImages),
            CanvasMenuEntry(key: "rotate-right", title: "顺时针旋转", enabled: hasImages),
            CanvasMenuEntry(key: "delete", title: "删除", enabled: hasImages),
            CanvasMenuEntry(key: "-", title: ""),
            CanvasMenuEntry(key: "properties", title: "属性", enabled: hasImages),
            CanvasMenuEntry(key: "options", title: "选项"),
        ]
    }

    func refreshRecent() {
        recent = store.recentFolders
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            .filter { url in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                    && isDirectory.boolValue
            }
    }

    func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "打开"
        panel.message = "选择包含图片的文件夹"
        if let folder { panel.directoryURL = folder }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadFolder(url)
    }

    func openImagePanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "打开"
        panel.message = "选择一张图片"
        if let folder { panel.directoryURL = folder }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openImage(url)
    }

    func loadFolder(_ url: URL) {
        let folderURL = url.standardizedFileURL
        do {
            let items = try ImageLibrary.scan(folder: folderURL, rotations: store.allRotations)
            guard !items.isEmpty else {
                alertMessage = "这个文件夹里没有可显示的图片"
                return
            }
            images = items
            folder = folderURL
            index = 0
            if settings.rememberRecent {
                store.remember(folder: folderURL)
                refreshRecent()
            }
            loadCurrent(fit: settings.fitOnOpen)
        } catch {
            alertMessage = "无法打开文件夹：\(error.localizedDescription)"
        }
    }

    func openImage(_ url: URL) {
        let parent = url.deletingLastPathComponent()
        do {
            let items = try ImageLibrary.scan(folder: parent, rotations: store.allRotations)
            guard let position = items.firstIndex(where: { $0.url.path == url.standardizedFileURL.path }) else {
                alertMessage = "无法打开这张图片"
                return
            }
            images = items
            folder = parent
            index = position
            if settings.rememberRecent {
                store.remember(folder: parent)
                refreshRecent()
            }
            loadCurrent(fit: settings.fitOnOpen)
        } catch {
            alertMessage = "无法打开图片：\(error.localizedDescription)"
        }
    }

    func loadCurrent(fit: Bool? = nil) {
        guard let item = current else {
            canvas.clear()
            slideshowImage = nil
            return
        }
        let token = loadToken + 1
        loadToken = token
        let shouldFit = fit ?? settings.fitOnOpen
        canvas.setImage(nil, rotation: item.rotation, fit: shouldFit)
        let url = item.url
        ImageLoader.shared.load(url: url, maxPixel: 4096) { [weak self] loaded in
            guard let self, self.loadToken == token else { return }
            guard let loaded else {
                self.alertMessage = "无法显示这张图片，格式可能不受支持"
                return
            }
            let rotation = self.current?.rotation ?? item.rotation
            self.canvas.setImage(loaded.image, rotation: rotation, fit: shouldFit)
            ImageLoader.shared.load(url: url, maxPixel: 0) { [weak self] full in
                guard let self, self.loadToken == token, let full else { return }
                self.canvas.replaceImage(full.image)
            }
        }
    }

    func goNext() {
        guard canGoNext else { return }
        index += 1
        loadCurrent(fit: true)
    }

    func goPrevious() {
        guard canGoPrevious else { return }
        index -= 1
        loadCurrent(fit: true)
    }

    func goFirst() {
        guard hasImages else { return }
        index = 0
        loadCurrent(fit: true)
    }

    func goLast() {
        guard hasImages else { return }
        index = images.count - 1
        loadCurrent(fit: true)
    }

    func rotate(_ delta: Int) {
        guard var item = current else { return }
        let angle = ((item.rotation + delta) % 360 + 360) % 360
        store.setRotation(angle, for: item.url)
        item.rotation = angle
        images[index] = item
        canvas.setRotation(angle)
    }

    func deleteCurrent() {
        guard let item = current else { return }
        let alert = NSAlert()
        alert.messageText = "删除图片"
        alert.informativeText = "要把“\(item.name)”放入废纸篓吗？原文件会从当前文件夹移除。"
        alert.addButton(withTitle: "放入废纸篓")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
        } catch {
            alertMessage = "删除失败：\(error.localizedDescription)"
            return
        }
        store.forgetRotation(for: item.url)
        images.remove(at: index)
        if images.isEmpty {
            index = 0
            canvas.clear()
        } else {
            index = min(index, images.count - 1)
            loadCurrent(fit: true)
        }
    }

    func copyImage() {
        guard let image = canvas.image else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    func copyPath() {
        guard let item = current else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.url.path, forType: .string)
    }

    func revealInFinder() {
        guard let item = current else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func saveAs() {
        guard let item = current else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.name
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        if destination.standardizedFileURL == item.url.standardizedFileURL { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: item.url, to: destination)
        } catch {
            alertMessage = "另存为失败：\(error.localizedDescription)"
        }
    }

    func setAsWallpaper() {
        guard let item = current, let screen = NSScreen.main else { return }
        do {
            try NSWorkspace.shared.setDesktopImageURL(item.url, for: screen, options: [:])
        } catch {
            alertMessage = "设置桌面背景失败：\(error.localizedDescription)"
        }
    }

    func showProperties() {
        guard let item = current else { return }
        let attributes = try? FileManager.default.attributesOfItem(atPath: item.url.path)
        var width: Int?
        var height: Int?
        if let source = CGImageSourceCreateWithURL(item.url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
            height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        }
        properties = ImageProperties(
            name: item.name,
            path: item.url.path,
            format: item.url.pathExtension.uppercased(),
            width: width,
            height: height,
            bytes: (attributes?[.size] as? NSNumber)?.int64Value,
            modified: attributes?[.modificationDate] as? Date,
            rotation: item.rotation
        )
        showingProperties = true
    }

    func openOptions() {
        showingOptions = true
    }

    func apply(settings newSettings: AppSettings) {
        let validated = newSettings.validated()
        settings = validated
        store.settings = validated
    }

    func handleMenu(_ key: String) {
        switch key {
        case "open-folder": openFolderPanel()
        case "copy": copyImage()
        case "copy-path": copyPath()
        case "reveal": revealInFinder()
        case "save-as": saveAs()
        case "wallpaper": setAsWallpaper()
        case "rotate-left": rotate(-90)
        case "rotate-right": rotate(90)
        case "delete": deleteCurrent()
        case "properties": showProperties()
        case "options": openOptions()
        default: break
        }
    }

    func startSlideshow() {
        SlideshowController.shared.start(model: self)
    }

    func stopSlideshow() {
        SlideshowController.shared.stop()
        isSlideshowRunning = false
    }

    func showSlideshowImage(at position: Int) {
        guard images.indices.contains(position) else { return }
        index = position
        slideshowImage = nil
        let url = images[position].url
        ImageLoader.shared.load(url: url, maxPixel: 3200) { [weak self] loaded in
            guard let self, self.index == position else { return }
            self.slideshowImage = loaded?.image
        }
    }

    func dismissAlert() {
        alertMessage = nil
    }
}

func formatByteCount(_ bytes: Int64?) -> String {
    guard let bytes else { return "未知" }
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}
