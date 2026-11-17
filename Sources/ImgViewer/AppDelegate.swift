import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSWindowDelegate {
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        installMonitor()
        if !openLaunchArgumentIfNeeded() && contexts.isEmpty {
            makeWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
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
        contexts.removeAll { $0.window === window }
    }

    // MARK: 窗口

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
        panel.minSize = NSSize(width: 1100, height: 600)
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: content)

        if let last = contexts.last {
            let lastFrame = last.window.frame
            let screen = last.window.screen ?? NSScreen.main
            let visible = screen?.visibleFrame ?? lastFrame
            let sideBySideX = lastFrame.maxX + 12
            if sideBySideX + panel.frame.width <= visible.maxX {
                panel.setFrameTopLeftPoint(NSPoint(x: sideBySideX, y: lastFrame.maxY))
            } else {
                panel.setFrameTopLeftPoint(NSPoint(x: lastFrame.minX + 28, y: lastFrame.maxY - 28))
            }
        } else {
            panel.center()
        }

        panel.makeKeyAndOrderFront(nil)

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
        fileMenu.addItem(.separator())
        add(fileMenu, "另存为…", #selector(saveAs), "s", [.command, .shift])
        add(fileMenu, "属性", #selector(showProperties), "i", .command)
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
             #selector(showProperties), #selector(deleteImage),
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

    @objc private func startSlideshow() { modelForAction.startSlideshow() }

    @objc private func toggleSlideshowPause() { SlideshowController.shared.togglePause() }

    @objc private func stopSlideshow() { SlideshowController.shared.stop() }
}
