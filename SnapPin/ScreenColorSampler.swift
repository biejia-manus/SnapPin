import Cocoa

/// A composited screen pixel expressed as 8-bit sRGB. A screen has no recoverable
/// source-layer transparency, so its CSS RGBA alpha is always 1.
struct ScreenColor: Equatable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    var hex: String {
        String(format: "#%02X%02X%02X", Int(red), Int(green), Int(blue))
    }

    var rgba: String { "rgba(\(red), \(green), \(blue), 1)" }

    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255,
                blue: CGFloat(blue) / 255, alpha: 1)
    }
}

enum ScreenColorFormat {
    case hex, rgba

    func string(for color: ScreenColor) -> String {
        switch self {
        case .hex: return color.hex
        case .rgba: return color.rgba
        }
    }
}

enum ScreenColorSampler {
    /// Convert bottom-left AppKit coordinates into top-left image pixels. Use the
    /// actual image dimensions, not a hard-coded Retina factor or the main screen.
    static func pixelRect(at point: NSPoint, in bounds: NSRect, imageWidth: Int, imageHeight: Int) -> CGRect? {
        guard point.x.isFinite, point.y.isFinite,
              bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0,
              imageWidth > 0, imageHeight > 0, bounds.contains(point) else { return nil }

        let x = min(imageWidth - 1, Int(floor((point.x - bounds.minX) / bounds.width * CGFloat(imageWidth))))
        let y = imageHeight - 1 - min(imageHeight - 1,
            Int(floor((point.y - bounds.minY) / bounds.height * CGFloat(imageHeight))))
        return CGRect(x: x, y: y, width: 1, height: 1)
    }

    static func sample(at point: NSPoint, in bounds: NSRect, image: CGImage) -> ScreenColor? {
        guard let rect = pixelRect(at: point, in: bounds, imageWidth: image.width, imageHeight: image.height),
              let pixel = image.cropping(to: rect),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        // Convert just one pixel. Never assume the capture's byte order, bit depth,
        // or color profile (e.g. Display P3), and never sample the dimmed overlay.
        var bytes = [UInt8](repeating: 0, count: 4)
        let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1,
                                          bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace,
                                          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
                                              CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.interpolationQuality = .none
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard rendered else { return nil }
        return ScreenColor(red: bytes[0], green: bytes[1], blue: bytes[2])
    }
}
