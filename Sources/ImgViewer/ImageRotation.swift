import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ImageRotation {
    static func rotated(_ image: NSImage, degrees: Int) -> NSImage {
        let angle = ((degrees % 360) + 360) % 360
        guard angle != 0,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }
        let output = rotated(cgImage, degrees: angle)
        return NSImage(cgImage: output, size: NSSize(width: output.width, height: output.height))
    }

    static func rotated(_ image: CGImage, degrees: Int) -> CGImage {
        let angle = ((degrees % 360) + 360) % 360
        guard angle != 0 else { return image }
        let swapped = angle % 180 != 0
        let width = swapped ? image.height : image.width
        let height = swapped ? image.width : image.height
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        context.rotate(by: CGFloat(angle) * .pi / 180)
        context.draw(
            image,
            in: CGRect(
                x: -CGFloat(image.width) / 2,
                y: -CGFloat(image.height) / 2,
                width: CGFloat(image.width),
                height: CGFloat(image.height)
            )
        )
        return context.makeImage() ?? image
    }

    static func write(_ image: NSImage, degrees: Int, to url: URL) -> Bool {
        let rotatedImage = rotated(image, degrees: degrees)
        guard let cgImage = rotatedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }
        let type = UTType(filenameExtension: url.pathExtension.lowercased()) ?? .png
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            type.identifier as CFString,
            1,
            nil
        ) else { return false }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.92]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }
}
