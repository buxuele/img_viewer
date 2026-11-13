import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var window: NSWindow?
    private var monitor: Any?
    private var cancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        buildWindow()
        installMonitor()
        openLaunchArgumentIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        open(url)
    }

    private func buildWindow() {
        let model = AppModel.shared
        let content = ContentView().environmentObject(model)
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = model.windowTitle
        panel.minSize = NSSize(width: 1100, height: 600)
        panel.contentView = NSHostingView(rootView: content)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        window = panel

        cancellable = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, let window = self.window else { return }
                window.title = AppModel.shared.windowTitle
            }
        }
    }

    private func openLaunchArgumentIfNeeded() {
        guard let path = CommandLine.arguments.dropFirst().first,
              !path.hasPrefix("-"),
              FileManager.default.fileExists(atPath: path) else { return }
        open(URL(fileURLWithPath: path))
    }

    private func open(_ url: URL) {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if isDirectory.boolValue {
            AppModel.shared.loadFolder(url)
        } else {
            AppModel.shared.openImage(url)
        }
    }

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
        let model = AppModel.shared
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
        if let responder = NSApp.keyWindow?.firstResponder, responder is NSTextView {
            return false
        }
        let model = AppModel.shared
        guard let action = menuItem.action else { return true }
        switch action {
        case #selector(previousImage):
            return model.canGoPrevious
        case #selector(nextImage):
            return model.canGoNext
        case #selector(firstImage), #selector(lastImage):
            return model.hasImages
        case #selector(copyImage), #selector(copyPath), #selector(saveAs),
             #selector(showProperties), #selector(deleteImage),
             #selector(rotateClockwise), #selector(rotateCounterClockwise):
            return model.hasImages
        case #selector(zoomIn), #selector(zoomOut), #selector(fitWindow), #selector(actualSize):
            return model.hasImages
        case #selector(startSlideshow):
            return model.hasImages && !SlideshowController.shared.isRunning
        case #selector(toggleSlideshowPause), #selector(stopSlideshow):
            return SlideshowController.shared.isRunning
        default:
            return true
        }
    }

    // MARK: 动作

    @objc private func openFolder() { AppModel.shared.openFolderPanel() }

    @objc private func openImage() { AppModel.shared.openImagePanel() }

    @objc private func saveAs() { AppModel.shared.saveAs() }

    @objc private func showProperties() { AppModel.shared.showProperties() }

    @objc private func showOptions() { AppModel.shared.openOptions() }

    @objc private func copyImage() { AppModel.shared.copyImage() }

    @objc private func copyPath() { AppModel.shared.copyPath() }

    @objc private func previousImage() { AppModel.shared.goPrevious() }

    @objc private func nextImage() { AppModel.shared.goNext() }

    @objc private func firstImage() { AppModel.shared.goFirst() }

    @objc private func lastImage() { AppModel.shared.goLast() }

    @objc private func zoomIn() { AppModel.shared.canvas.zoomIn() }

    @objc private func zoomOut() { AppModel.shared.canvas.zoomOut() }

    @objc private func fitWindow() { AppModel.shared.canvas.fitToWindow() }

    @objc private func actualSize() { AppModel.shared.canvas.actualSize() }

    @objc private func rotateClockwise() { AppModel.shared.rotate(90) }

    @objc private func rotateCounterClockwise() { AppModel.shared.rotate(-90) }

    @objc private func deleteImage() { AppModel.shared.deleteCurrent() }

    @objc private func startSlideshow() { AppModel.shared.startSlideshow() }

    @objc private func toggleSlideshowPause() { SlideshowController.shared.togglePause() }

    @objc private func stopSlideshow() { SlideshowController.shared.stop() }
}
