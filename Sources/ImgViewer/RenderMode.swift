import AppKit
import SwiftUI

@MainActor
enum RenderMode {
    static func run() {
        NSApp.appearance = NSAppearance(named: .aqua)
        let arguments = CommandLine.arguments
        let output = URL(fileURLWithPath: value(after: "--out", in: arguments) ?? "效果图", isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let folder = value(after: "--folder", in: arguments).map { URL(fileURLWithPath: $0) }

        renderViewer(folder: folder, output: output.appendingPathComponent("01-查看器.png"))
        renderEmpty(folder: folder, output: output.appendingPathComponent("02-图片库.png"))
        renderSlideshow(folder: folder, output: output.appendingPathComponent("03-幻灯片.png"))
        renderOptions(output: output.appendingPathComponent("04-选项.png"))
    }

    private static func renderViewer(folder: URL?, output: URL) {
        let model = makeModel()
        if let folder {
            model.loadFolder(folder)
            pump(until: { model.canvas.hasImage }, timeout: 8)
            model.canvas.fitToWindow()
            pump(seconds: 0.3)
        }
        let view = ContentView()
            .environmentObject(model)
            .frame(width: 1200, height: 800)
        write(view, size: NSSize(width: 1200, height: 800), to: output)
    }

    private static func renderEmpty(folder: URL?, output: URL) {
        let model = makeModel()
        if let folder {
            model.store.remember(folder: folder)
            model.refreshRecent()
        }
        let view = ContentView()
            .environmentObject(model)
            .frame(width: 1200, height: 800)
        write(view, size: NSSize(width: 1200, height: 800), to: output)
    }

    private static func renderSlideshow(folder: URL?, output: URL) {
        let model = makeModel()
        guard let folder else { return }
        var settings = model.settings
        settings.slideshowTheme = "gradient"
        model.apply(settings: settings)
        model.loadFolder(folder)
        pump(until: { model.hasImages }, timeout: 8)
        model.showSlideshowImage(at: 0)
        pump(until: { model.slideshowImage != nil }, timeout: 8)
        let view = SlideshowView(model: model, controller: SlideshowController.shared)
            .frame(width: 1200, height: 800)
        write(view, size: NSSize(width: 1200, height: 800), to: output)
    }

    private static func renderOptions(output: URL) {
        let model = makeModel()
        let view = OptionsView(model: model)
            .background(Color(nsColor: .windowBackgroundColor))
        write(view, size: NSSize(width: 480, height: 380), to: output)
    }

    private static func makeModel() -> AppModel {
        let suite = "imgviewer.render.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("imgviewer-render-\(UUID().uuidString)", isDirectory: true)
        return AppModel(store: SettingsStore(defaults: defaults, directory: directory))
    }

    private static func write<V: View>(_ view: V, size: NSSize, to url: URL) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        pump(seconds: 0.2)
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }

    private static func pump(seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        }
    }

    private static func pump(until condition: @escaping () -> Bool, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
