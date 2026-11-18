import Foundation

enum WindowPolicy {
    static let minimumSize = CGSize(width: 680, height: 500)

    static func tiledFrames(in visible: CGRect, gap: CGFloat = 12) -> [CGRect] {
        let width = max(320, (visible.width - gap * 3) / 2)
        let height = max(320, visible.height - gap * 2)
        return [
            CGRect(x: visible.minX + gap, y: visible.minY + gap, width: width, height: height),
            CGRect(x: visible.minX + gap * 2 + width, y: visible.minY + gap, width: width, height: height),
        ]
    }

    static func cascadedFrame(size: CGSize, after previous: CGRect, in visible: CGRect) -> CGRect {
        let x = previous.minX + 28
        let y = previous.maxY - 28 - size.height
        return CGRect(
            x: min(max(x, visible.minX + 8), max(visible.minX + 8, visible.maxX - size.width - 8)),
            y: min(max(y, visible.minY + 8), max(visible.minY + 8, visible.maxY - size.height - 8)),
            width: size.width,
            height: size.height
        )
    }
}
