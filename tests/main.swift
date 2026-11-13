import AppKit
import Foundation

var failures = 0

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("通过 \(message)")
    } else {
        failures += 1
        print("失败 \(message)")
    }
}

let root = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("imgviewer-tests-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }

let photos = root.appendingPathComponent("photos", isDirectory: true)
try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
for name in ["图10.png", "图2.png", "图1.PNG", "备注.txt", ".hidden.jpg", "照片.heic"] {
    FileManager.default.createFile(atPath: photos.appendingPathComponent(name).path, contents: Data("x".utf8))
}

let folder = root.appendingPathComponent("album", isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

expect(ImageLibrary.isImage(URL(fileURLWithPath: "/a/b.JPG")), "扩展名大小写不敏感")
expect(!ImageLibrary.isImage(URL(fileURLWithPath: "/a/b.txt")), "非图片被排除")
expect(
    ["图10.png", "图2.png", "图1.png"].sorted(by: ImageLibrary.naturalCompare) == ["图1.png", "图2.png", "图10.png"],
    "自然排序按数字大小"
)

let scanned = try ImageLibrary.scan(folder: photos, rotations: [photos.appendingPathComponent("图2.png").path: 90])
expect(scanned.map(\.name) == ["图1.PNG", "图2.png", "图10.png", "照片.heic"], "扫描结果排序且过滤隐藏与非图片")
expect(scanned.count == 4, "扫描数量为四")
expect(scanned.first(where: { $0.name == "图2.png" })?.rotation == 90, "扫描带回已保存的旋转角度")

let suiteName = "imgviewer-tests-\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suiteName)!
let store = SettingsStore(defaults: defaults, directory: root.appendingPathComponent("support", isDirectory: true))
expect(store.settings.fitOnOpen, "默认打开时适应窗口")
expect(store.settings.slideshowInterval == 5, "默认幻灯片间隔为五秒")

var changed = store.settings
changed.background = "black"
changed.slideshowInterval = 99
changed.slideshowTheme = "unknown"
store.settings = changed
expect(store.settings.background == "black", "设置持久化背景")
expect(store.settings.slideshowInterval == 60, "间隔上限被压到六十秒")
expect(store.settings.slideshowTheme == "black", "非法主题回落到黑色")

let imageURL = photos.appendingPathComponent("图1.PNG")
store.setRotation(450, for: imageURL)
expect(store.rotation(for: imageURL) == 90, "旋转角度归一化到三百六十度内")

let reopened = SettingsStore(defaults: defaults, directory: root.appendingPathComponent("support", isDirectory: true))
expect(reopened.rotation(for: imageURL) == 90, "旋转角度写入磁盘后可读回")

store.remember(folder: photos)
store.remember(folder: photos)
expect(store.recentFolders.filter { $0 == photos.path }.count == 1, "最近文件夹不重复")
expect(store.recentFolders.first == photos.path, "最近文件夹置顶")

defaults.removePersistentDomain(forName: suiteName)

MainActor.assumeIsolated {
    let canvas = CanvasState()
    canvas.setViewSize(CGSize(width: 1000, height: 800))
    canvas.setImage(NSImage(size: NSSize(width: 2000, height: 1000)), rotation: 0, fit: true)
    expect(abs(canvas.scale - canvas.fitScale) < 0.001, "打开时按窗口适应")
    let fitted = canvas.scale

    canvas.zoom(to: 1, anchor: CGPoint(x: 750, y: 400))
    let expectedPan = 250 - 250 * (1 / fitted)
    expect(abs(canvas.offset.width - expectedPan) < 0.001, "滚轮缩放以光标为锚点补偿偏移")

    canvas.setOffset(CGSize(width: 9999, height: 9999))
    expect(canvas.offset.width == 500, "水平平移被限制在边界")
    expect(canvas.offset.height == 100, "垂直平移被限制在边界")

    canvas.setRotation(90)
    canvas.fitToWindow()
    expect(abs(canvas.scale - canvas.fitScale) < 0.001, "旋转九十度后按交换后的尺寸适应")

    canvas.actualSize()
    expect(canvas.scale == 1 && canvas.offset == .zero, "实际大小回到百分之百并居中")

    canvas.toggleZoom()
    expect(canvas.mode == .fit, "双击切换回适应窗口")
}

if failures > 0 {
    print("失败 \(failures) 项")
    exit(1)
}
print("全部逻辑测试通过")
