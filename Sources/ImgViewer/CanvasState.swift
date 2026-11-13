import AppKit
import Combine
import CoreGraphics
import Foundation

@MainActor
final class CanvasState: ObservableObject {
    enum ZoomMode {
        case fit
        case manual
    }

    @Published private(set) var image: NSImage?
    @Published private(set) var scale: CGFloat = 1
    @Published private(set) var offset: CGSize = .zero
    @Published private(set) var rotation: Int = 0
    @Published private(set) var imageSize: CGSize = .zero
    @Published private(set) var mode: ZoomMode = .fit

    let minimumScale: CGFloat = 0.02
    let maximumScale: CGFloat = 8

    var viewSize: CGSize = .zero

    var hasImage: Bool { image != nil && imageSize.width > 0 && imageSize.height > 0 }

    var percent: Int { Int((scale * 100).rounded()) }

    var fitScale: CGFloat {
        guard hasImage, viewSize.width > 0, viewSize.height > 0 else { return 1 }
        let swapped = rotation % 180 != 0
        let width = swapped ? imageSize.height : imageSize.width
        let height = swapped ? imageSize.width : imageSize.height
        let available = CGSize(width: max(120, viewSize.width - 28), height: max(120, viewSize.height - 24))
        return min(available.width / width, available.height / height, 1)
    }

    var displayedSize: CGSize {
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return rotation % 180 == 0
            ? CGSize(width: width, height: height)
            : CGSize(width: height, height: width)
    }

    var canPan: Bool {
        guard hasImage, viewSize.width > 0 else { return false }
        let size = displayedSize
        return size.width > viewSize.width + 1 || size.height > viewSize.height + 1
    }

    func setViewSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0, size != viewSize else { return }
        viewSize = size
        if mode == .fit {
            scale = fitScale
            offset = .zero
        } else {
            clampOffset()
        }
    }

    func setImage(_ image: NSImage?, rotation: Int, fit: Bool) {
        self.image = image
        self.rotation = ((rotation % 360) + 360) % 360
        imageSize = image?.size ?? .zero
        mode = fit ? .fit : .manual
        scale = fit ? fitScale : 1
        offset = .zero
    }

    func replaceImage(_ image: NSImage) {
        self.image = image
        imageSize = image.size
        if mode == .fit {
            scale = fitScale
            offset = .zero
        } else {
            clampOffset()
        }
    }

    func clear() {
        image = nil
        imageSize = .zero
        scale = 1
        offset = .zero
        rotation = 0
        mode = .fit
    }

    func setRotation(_ degrees: Int) {
        rotation = ((degrees % 360) + 360) % 360
        if mode == .fit {
            scale = fitScale
            offset = .zero
        } else {
            clampOffset()
        }
    }

    func fitToWindow() {
        mode = .fit
        scale = fitScale
        offset = .zero
    }

    func actualSize() {
        mode = .manual
        scale = 1
        offset = .zero
        clampOffset()
    }

    func toggleZoom() {
        if mode == .fit {
            actualSize()
        } else {
            fitToWindow()
        }
    }

    func zoom(to target: CGFloat, anchor: CGPoint? = nil) {        guard hasImage else { return }
        let clamped = min(maximumScale, max(minimumScale, target))
        let point = anchor ?? CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        let centerX = point.x - viewSize.width / 2
        let centerY = point.y - viewSize.height / 2
        let ratio = clamped / scale
        offset = CGSize(
            width: centerX - (centerX - offset.width) * ratio,
            height: centerY - (centerY - offset.height) * ratio
        )
        scale = clamped
        mode = .manual
        clampOffset()
    }

    func zoomIn() {
        let target = CanvasState.steps.first(where: { $0 > scale + 0.001 }) ?? maximumScale
        zoom(to: target)
    }

    func zoomOut() {
        let target = CanvasState.steps.last(where: { $0 < scale - 0.001 }) ?? minimumScale
        zoom(to: target)
    }

    static let steps: [CGFloat] = [
        0.1, 0.15, 0.25, 0.33, 0.5, 0.66, 0.75, 1,
        1.25, 1.5, 2, 2.5, 3, 4, 5, 6, 8,
    ]

    func setOffset(_ newOffset: CGSize) {
        offset = newOffset
        clampOffset()
    }

    func pan(by delta: CGSize) {
        setOffset(CGSize(width: offset.width + delta.width, height: offset.height + delta.height))
    }

    func clampOffset() {
        guard hasImage, viewSize.width > 0 else {
            offset = .zero
            return
        }
        let size = displayedSize
        let maxX = max(0, (size.width - viewSize.width) / 2)
        let maxY = max(0, (size.height - viewSize.height) / 2)
        offset = CGSize(
            width: min(maxX, max(-maxX, offset.width)),
            height: min(maxY, max(-maxY, offset.height))
        )
    }
}
