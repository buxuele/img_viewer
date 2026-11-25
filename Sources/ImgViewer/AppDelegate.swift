import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSWindowDelegate, NSMenuDelegate {
    private final class WindowContext {
        let window: NSWindow
        let model: AppModel
        var cancellable: AnyCancellable?

        init(window: NSWindow, model: AppModel) {
            self.window = window
            self.model = model
        }
    }

    private var contexts: [WindowContext] = []
    private var monitor: Any?
    private weak var recentMenu: NSMenu?
    private var snapshotMode = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        installMonitor()

        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--snapshot"),
           arguments.indices.contains(index + 1) {
            snapshotMode = true
            let output = arguments[index + 1]
            if arguments.indices.contains(index + 2) {
                open(URL(fileURLWithPath: arguments[index + 2]))
            }
            if contexts.isEmpty {
                makeWindow()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.captureActiveWindow(to: output)
                NSApp.terminate(nil)
            }
            return
        }

        if !openLaunchArgumentIfNeeded() && contexts.isEmpty {
            makeWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func captureActiveWindow(to path: String) {
        guard let window = activeContext?.window,
              let frameView = window.contentView?.superview else { return }
        frameView.layoutSubtreeIfNeeded()
        guard let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        decorateTrafficLights(in: rep, window: window, frameView: frameView)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    private func decorateTrafficLights(in rep: NSBitmapImageRep, window: NSWindow, frameView: NSView) {
        let buttons: [(NSWindow.ButtonType, NSColor)] = [
            (.closeButton, NSColor(srgbRed: 1.0, green: 0.37, blue: 0.34, alpha: 1)),
            (.miniaturizeButton, NSColor(srgbRed: 1.0, green: 0.74, blue: 0.18, alpha: 1)),
            (.zoomButton, NSColor(srgbRed: 0.16, green: 0.78, blue: 0.25, alpha: 1)),
        ]
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        for (type, color) in buttons {
            guard let button = window.standardWindowButton(type) else { continue }
            let rect = button.convert(button.bounds, to: frameView)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(rect.width, rect.height) / 2
            let circle = NSBezierPath(ovalIn: NSRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            color.setFill()
            circle.fill()
            (color.blended(withFraction: 0.12, of: .black) ?? color).setStroke()
            circle.lineWidth = 1
            circle.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if contexts.isEmpty || !flag {
            makeWindow()
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            open(url)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if let context = contexts.first(where: { $0.window === window }) {
            context.model.window = nil
        }
        if SlideshowController.shared.ownerWindow === window {
            SlideshowController.shared.stop()
        }
        saveWindowFrame(window)
        contexts.removeAll { $0.window === window }
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        saveWindowFrame(window)
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        saveWindowFrame(window)
    }

    private func saveWindowFrame(_ window: NSWindow) {
        guard contexts.contains(where: { $0.window === window }) else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "windowFrame")
    }

    private var activeContext: WindowContext? {
        if let key = NSApp.keyWindow {
            if let context = contexts.first(where: { $0.window === key }) {
                return context
            }
            if let parent = key.sheetParent,
               let context = contexts.first(where: { $0.window === parent }) {
                return context
            }
        }
        if let main = NSApp.mainWindow,
           let context = contexts.first(where: { $0.window === main }) {
            return context
        }
        return contexts.last
    }

    private var activeModel: AppModel? {
        activeContext?.model
    }

    private var modelForAction: AppModel {
        activeModel ?? makeWindow()
    }

    @discardableResult
    private func makeWindow(model: AppModel? = nil) -> AppModel {
        let session = model ?? AppModel()
        session.requestOpen = { [weak self, weak session] url in
            guard let self, let session else { return }
            self.open(url, reusing: session)
        }

        let content = ContentView().environmentObject(session)
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = session.windowTitle
        panel.minSize = WindowPolicy.minimumSize
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        session.window = panel
        let hosting = DropHostingView(rootView: content)
        hosting.onDrop = { [weak self] urls in
            guard let self else { return }
            for url in urls {
                self.open(url)
            }
        }
        panel.contentView = hosting

        if contexts.count == 1, let existing = contexts.first, let screen = existing.window.screen ?? NSScreen.main {
            let frames = WindowPolicy.tiledFrames(in: screen.visibleFrame)
            existing.window.setFrame(frames[0], display: true)
            panel.setFrame(frames[1], display: true)
        } else if let last = contexts.last {
            let visible = (last.window.screen ?? NSScreen.main)?.visibleFrame ?? last.window.frame
            let frame = WindowPolicy.cascadedFrame(size: panel.frame.size, after: last.window.frame, in: visible)
            panel.setFrame(frame, display: false)
        } else if let saved = UserDefaults.standard.string(forKey: "windowFrame") {
            let frame = NSRectFromString(saved)
            if frame.width >= WindowPolicy.minimumSize.width,
               frame.height >= WindowPolicy.minimumSize.height {
                panel.setFrame(frame, display: false)
            } else {
                panel.center()
            }
        } else {
            panel.center()
        }

        if snapshotMode {
            panel.setFrameOrigin(NSPoint(x: -6000, y: -6000))
            panel.orderFront(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }

        let context = WindowContext(window: panel, model: session)
        context.cancellable = session.objectWillChange.sink { [weak panel, weak session] _ in
            DispatchQueue.main.async {
                guard let panel, let session else { return }
                panel.title = session.windowTitle
            }
        }
        contexts.append(context)
        return session
    }

    private func modelForOpen(preferred: AppModel?) -> AppModel {
        if let preferred, !preferred.hasImages {
            return preferred
        }
        if let active = activeModel, !active.hasImages {
            return active
        }
        return makeWindow()
    }

    private func open(_ url: URL, reusing model: AppModel? = nil) {
        let target = modelForOpen(preferred: model)
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if isDirectory.boolValue {
            target.loadFolder(url)
        } else {
            target.openImage(url)
        }
    }

    private func openLaunchArgumentIfNeeded() -> Bool {
        guard let path = CommandLine.arguments.dropFirst().first,
              !path.hasPrefix("-"),
              FileManager.default.fileExists(atPath: path) else { return false }
        open(URL(fileURLWithPath: path))
        return true
    }

    // MARK: 键盘

    private func installMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated {
                self.handle(event) ? nil : event
            }
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        if let responder = NSApp.keyWindow?.firstResponder, responder is NSTextView {
            return false
        }
        if NSApp.modalWindow != nil {
            return false
        }
        if let key = NSApp.keyWindow, key.sheetParent != nil {
            return false
        }

        let slideshow = SlideshowController.shared
        if slideshow.isRunning {
            switch event.keyCode {
            case 53:
                slideshow.stop()
                return true
            case 49:
                slideshow.togglePause()
                return true
            case 123, 116:
                slideshow.advance(-1)
                return true
            case 124, 121:
                slideshow.advance(1)
                return true
            default:
                return false
            }
        }

        guard let model = activeModel else { return false }

        switch event.keyCode {
        case 123, 116:
            model.goPrevious()
            return true
        case 124, 121:
            model.goNext()
            return true
        case 115:
            model.goFirst()
            return true
        case 119:
            model.goLast()
            return true
        case 51, 117:
            model.deleteCurrent()
            return true
        case 103:
            model.startSlideshow()
            return true
        default:
            break
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.isEmpty, let characters = event.charactersIgnoringModifiers {
            if characters == "+" || characters == "=" {
                model.canvas.zoomIn()
                return true
            }
            if characters == "-" || characters == "_" {
                model.canvas.zoomOut()
                return true
            }
            if characters == "0" {
                model.canvas.fitToWindow()
                return true
            }
            if characters == "1" {
                model.canvas.actualSize()
                return true
            }
        }
        return false
    }

    // MARK: 菜单

    private func buildMenu() {
        let mainMenu = NSMenu()
        let appName = "照片查看器"

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(
            withTitle: "关于 \(appName)",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        add(appMenu, "选项…", #selector(showOptions), ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出 \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "文件")
        fileItem.submenu = fileMenu
        add(fileMenu, "打开文件夹…", #selector(openFolder), "o", .command)
        add(fileMenu, "打开图片…", #selector(openImage), "o", [.command, .shift])
        let recentItem = NSMenuItem(title: "最近打开", action: nil, keyEquivalent: "")
        let recent = NSMenu(title: "最近打开")
        recent.delegate = self
        recentItem.submenu = recent
        recentMenu = recent
        fileMenu.addItem(recentItem)
        fileMenu.addItem(.separator())
        add(fileMenu, "另存为…", #selector(saveAs), "s", [.command, .shift])
        add(fileMenu, "属性", #selector(showProperties), "i", .command)
        add(fileMenu, "打印…", #selector(printImage), "p", .command)
        fileMenu.addItem(.separator())
        let closeItem = NSMenuItem(title: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenu.addItem(closeItem)

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editItem.submenu = editMenu
        add(editMenu, "复制图片", #selector(copyImage), "c", [.command, .shift])
        add(editMenu, "复制文件路径", #selector(copyPath), "c", [.command, .option])

        let imageItem = NSMenuItem()
        mainMenu.addItem(imageItem)
        let imageMenu = NSMenu(title: "图像")
        imageItem.submenu = imageMenu
        add(imageMenu, "上一张", #selector(previousImage), String(UnicodeScalar(NSLeftArrowFunctionKey)!))
        add(imageMenu, "下一张", #selector(nextImage), String(UnicodeScalar(NSRightArrowFunctionKey)!))
        add(imageMenu, "第一张", #selector(firstImage), String(UnicodeScalar(NSHomeFunctionKey)!))
        add(imageMenu, "最后一张", #selector(lastImage), String(UnicodeScalar(NSEndFunctionKey)!))
        imageMenu.addItem(.separator())
        add(imageMenu, "放大", #selector(zoomIn), "=", .command)
        add(imageMenu, "缩小", #selector(zoomOut), "-", .command)
        add(imageMenu, "适应窗口", #selector(fitWindow), "0", .command)
        add(imageMenu, "实际大小", #selector(actualSize), "1", .command)
        imageMenu.addItem(.separator())
        add(imageMenu, "顺时针旋转", #selector(rotateClockwise), "r", .command)
        add(imageMenu, "逆时针旋转", #selector(rotateCounterClockwise), "l", .command)
        add(imageMenu, "删除", #selector(deleteImage), String(UnicodeScalar(NSDeleteCharacter)!))

        let slideshowItem = NSMenuItem()
        mainMenu.addItem(slideshowItem)
        let slideshowMenu = NSMenu(title: "幻灯片")
        slideshowItem.submenu = slideshowMenu
        let startKey = String(UnicodeScalar(0xF70E)!)
        add(slideshowMenu, "开始幻灯片", #selector(startSlideshow), startKey)
        add(slideshowMenu, "暂停或继续", #selector(toggleSlideshowPause), "p", [.command, .option])
        add(slideshowMenu, "退出幻灯片", #selector(stopSlideshow), String(UnicodeScalar(0x1B)!))

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "窗口")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    @discardableResult
    private func add(
        _ menu: NSMenu,
        _ title: String,
        _ action: Selector,
        _ key: String,
        _ modifiers: NSEvent.ModifierFlags = []
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        menu.addItem(item)
        return item
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if NSApp.modalWindow != nil {
            return false
        }
        if let responder = NSApp.keyWindow?.firstResponder, responder is NSTextView {
            return false
        }
        guard let action = menuItem.action else { return true }
        let hasImages = activeModel?.hasImages ?? false
        switch action {
        case #selector(previousImage):
            return activeModel?.canGoPrevious ?? false
        case #selector(nextImage):
            return activeModel?.canGoNext ?? false
        case #selector(firstImage), #selector(lastImage):
            return hasImages
        case #selector(copyImage), #selector(copyPath), #selector(saveAs),
             #selector(showProperties), #selector(deleteImage), #selector(printImage),
             #selector(rotateClockwise), #selector(rotateCounterClockwise):
            return hasImages
        case #selector(zoomIn), #selector(zoomOut), #selector(fitWindow), #selector(actualSize):
            return hasImages
        case #selector(startSlideshow):
            return hasImages && !SlideshowController.shared.isRunning
        case #selector(toggleSlideshowPause), #selector(stopSlideshow):
            return SlideshowController.shared.isRunning
        case #selector(openFolder), #selector(openImage), #selector(showOptions):
            return true
        default:
            return true
        }
    }

    // MARK: 动作

    @objc private func openFolder() { modelForAction.openFolderPanel() }

    @objc private func openImage() { modelForAction.openImagePanel() }

    @objc private func saveAs() { modelForAction.saveAs() }

    @objc private func showProperties() { modelForAction.showProperties() }

    @objc private func showOptions() { modelForAction.openOptions() }

    @objc private func copyImage() { modelForAction.copyImage() }

    @objc private func copyPath() { modelForAction.copyPath() }

    @objc private func previousImage() { modelForAction.goPrevious() }

    @objc private func nextImage() { modelForAction.goNext() }

    @objc private func firstImage() { modelForAction.goFirst() }

    @objc private func lastImage() { modelForAction.goLast() }

    @objc private func zoomIn() { modelForAction.canvas.zoomIn() }

    @objc private func zoomOut() { modelForAction.canvas.zoomOut() }

    @objc private func fitWindow() { modelForAction.canvas.fitToWindow() }

    @objc private func actualSize() { modelForAction.canvas.actualSize() }

    @objc private func rotateClockwise() { modelForAction.rotate(90) }

    @objc private func rotateCounterClockwise() { modelForAction.rotate(-90) }

    @objc private func deleteImage() { modelForAction.deleteCurrent() }

    @objc private func printImage() { modelForAction.printCurrent() }

    @objc private func startSlideshow() { modelForAction.startSlideshow() }

    @objc private func toggleSlideshowPause() { SlideshowController.shared.togglePause() }

    @objc private func stopSlideshow() { SlideshowController.shared.stop() }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        modelForAction.openRecentFolder(path)
    }

    @objc private func clearRecent() {
        modelForAction.clearRecent()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === recentMenu else { return }
        menu.removeAllItems()
        let folders = activeModel?.store.recentFolders ?? []
        if folders.isEmpty {
            let empty = NSMenuItem(title: "无最近记录", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        for path in folders.prefix(10) {
            let item = NSMenuItem(
                title: URL(fileURLWithPath: path).lastPathComponent,
                action: #selector(openRecent(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = path
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "清除最近记录", action: #selector(clearRecent), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
    }
}
