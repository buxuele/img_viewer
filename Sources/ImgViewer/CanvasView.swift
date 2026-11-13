import AppKit
import Combine
import SwiftUI

struct CanvasMenuEntry {
    let key: String
    let title: String
    var enabled: Bool = true
}

struct ImageCanvas: NSViewRepresentable {
    @ObservedObject var canvas: CanvasState
    var background: String
    var wheelZoom: Bool
    var doubleClickZoom: Bool
    var menuEntries: [CanvasMenuEntry]
    var onMenuAction: (String) -> Void

    func makeNSView(context: Context) -> CanvasNSView {
        let view = CanvasNSView()
        view.canvas = canvas
        view.backgroundName = background
        view.wheelZoomEnabled = wheelZoom
        view.doubleClickZoomEnabled = doubleClickZoom
        view.menuEntries = menuEntries
        view.menuHandler = onMenuAction
        return view
    }

    func updateNSView(_ view: CanvasNSView, context: Context) {
        view.canvas = canvas
        view.backgroundName = background
        view.wheelZoomEnabled = wheelZoom
        view.doubleClickZoomEnabled = doubleClickZoom
        view.menuEntries = menuEntries
        view.menuHandler = onMenuAction
        view.needsDisplay = true
        view.window?.invalidateCursorRects(for: view)
    }
}

final class CanvasNSView: NSView {
    weak var canvas: CanvasState?
    var backgroundName = "light"
    var wheelZoomEnabled = true
    var doubleClickZoomEnabled = true
    var menuEntries: [CanvasMenuEntry] = []
    var menuHandler: ((String) -> Void)?

    private var cancellable: AnyCancellable?
    private var dragStart: CGPoint?
    private var dragOffset: CGSize = .zero
    private var isDragging = false

    private static let zoomSteps: [CGFloat] = [
        0.1, 0.15, 0.25, 0.33, 0.5, 0.66, 0.75, 1,
        1.25, 1.5, 2, 2.5, 3, 4, 5, 6, 8,
    ]

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        subscribe()
        window?.makeFirstResponder(self)
    }

    private func subscribe() {
        cancellable = nil
        guard let canvas else { return }
        cancellable = canvas.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.needsDisplay = true
                self.window?.invalidateCursorRects(for: self)
            }
        }
    }

    override func layout() {
        super.layout()
        canvas?.setViewSize(bounds.size)
    }

    override func draw(_ dirtyRect: NSRect) {
        let color: NSColor
        switch backgroundName {
        case "black": color = .black
        case "gray": color = NSColor(calibratedWhite: 0.34, alpha: 1)
        default: color = NSColor(calibratedWhite: 0.96, alpha: 1)
        }
        color.setFill()
        bounds.fill()

        guard let canvas, let image = canvas.image else { return }
        NSGraphicsContext.current?.imageInterpolation = .high
        let context = NSGraphicsContext.current!.cgContext
        context.saveGState()
        context.translateBy(x: bounds.midX + canvas.offset.width, y: bounds.midY + canvas.offset.height)
        context.rotate(by: CGFloat(canvas.rotation) * .pi / 180)
        let width = canvas.imageSize.width * canvas.scale
        let height = canvas.imageSize.height * canvas.scale
        let rect = NSRect(x: -width / 2, y: -height / 2, width: width, height: height)
        image.draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high.rawValue]
        )
        context.restoreGState()
    }

    override func resetCursorRects() {
        let cursor: NSCursor = canvas?.canPan == true ? .openHand : .arrow
        addCursorRect(bounds, cursor: cursor)
    }

    override func scrollWheel(with event: NSEvent) {
        guard wheelZoomEnabled, let canvas, canvas.hasImage else {
            super.scrollWheel(with: event)
            return
        }
        let delta = event.scrollingDeltaY
        guard abs(delta) > 0.01 else { return }
        let target: CGFloat
        if delta > 0 {
            target = Self.zoomSteps.first(where: { $0 > canvas.scale + 0.001 }) ?? canvas.maximumScale
        } else {
            target = Self.zoomSteps.last(where: { $0 < canvas.scale - 0.001 }) ?? canvas.minimumScale
        }
        canvas.zoom(to: target, anchor: convert(event.locationInWindow, from: nil))
    }

    override func magnify(with event: NSEvent) {
        guard let canvas, canvas.hasImage else { return }
        canvas.zoom(
            to: canvas.scale * (1 + event.magnification),
            anchor: convert(event.locationInWindow, from: nil)
        )
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let canvas, canvas.hasImage else { return }
        if event.clickCount == 2 && doubleClickZoomEnabled {
            canvas.toggleZoom()
            return
        }
        guard canvas.canPan else { return }
        dragStart = convert(event.locationInWindow, from: nil)
        dragOffset = canvas.offset
        isDragging = true
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let canvas, let start = dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        canvas.setOffset(CGSize(
            width: dragOffset.width + point.x - start.x,
            height: dragOffset.height + point.y - start.y
        ))
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            NSCursor.pop()
            isDragging = false
        }
        dragStart = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        guard !menuEntries.isEmpty else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in menuEntries {
            if entry.key == "-" {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: entry.title, action: #selector(activateMenuItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.key
            item.isEnabled = entry.enabled
            menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func activateMenuItem(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        menuHandler?(key)
    }
}
