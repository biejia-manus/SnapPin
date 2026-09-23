import CoreGraphics
import CoreVideo
import Foundation

/// ScreenCaptureKit supplies top-left-origin BGRA rows; selections use global,
/// bottom-left-origin AppKit points. Never use global points as byte offsets.
enum RecordingFrameCropper {
    static func pixelRect(for region: CGRect, on screenFrame: CGRect,
                          pixelWidth: Int, pixelHeight: Int) -> CGRect? {
        let values = [region.minX, region.minY, region.width, region.height,
                      region.maxX, region.maxY, screenFrame.minX, screenFrame.minY,
                      screenFrame.width, screenFrame.height, screenFrame.maxX, screenFrame.maxY]
        guard !region.isInfinite, !screenFrame.isInfinite, values.allSatisfy({ $0.isFinite }),
              region.width > 0, region.height > 0,
              screenFrame.width > 0, screenFrame.height > 0,
              pixelWidth > 0, pixelHeight > 0 else { return nil }
        let visible = region.intersection(screenFrame)
        guard !visible.isNull, !visible.isEmpty else { return nil }

        let scaleX = CGFloat(pixelWidth) / screenFrame.width
        let scaleY = CGFloat(pixelHeight) / screenFrame.height
        guard scaleX.isFinite, scaleY.isFinite else { return nil }
        let left = max(0, min(pixelWidth, Int(floor((visible.minX - screenFrame.minX) * scaleX))))
        let right = max(0, min(pixelWidth, Int(ceil((visible.maxX - screenFrame.minX) * scaleX))))
        let top = max(0, min(pixelHeight, Int(floor((screenFrame.maxY - visible.maxY) * scaleY))))
        let bottom = max(0, min(pixelHeight, Int(ceil((screenFrame.maxY - visible.minY) * scaleY))))
        guard right > left, bottom > top else { return nil }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// Copy each row into an owned allocation. A CVPixelBuffer wrapping a pointer
    /// into the input does NOT retain the input, and Core Image may read it later.
    static func crop(_ source: CVPixelBuffer, to region: CGRect, on screenFrame: CGRect) -> CVPixelBuffer? {
        guard CVPixelBufferGetPixelFormatType(source) == kCVPixelFormatType_32BGRA,
              !CVPixelBufferIsPlanar(source),
              let rect = pixelRect(for: region, on: screenFrame,
                                   pixelWidth: CVPixelBufferGetWidth(source),
                                   pixelHeight: CVPixelBufferGetHeight(source)) else { return nil }
        let width = Int(rect.width)
        let height = Int(rect.height)
        let sourceStride = CVPixelBufferGetBytesPerRow(source)
        let x = Int(rect.minX)
        let y = Int(rect.minY)
        guard sourceStride >= (x + width) * 4,
              y + height <= CVPixelBufferGetHeight(source) else { return nil }

        var destination: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                  attributes as CFDictionary, &destination) == kCVReturnSuccess,
              let destination = destination else { return nil }
        guard CVPixelBufferLockBaseAddress(source, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
        guard CVPixelBufferLockBaseAddress(destination, []) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(destination, []) }
        guard let sourceBase = CVPixelBufferGetBaseAddress(source),
              let destinationBase = CVPixelBufferGetBaseAddress(destination) else { return nil }

        let destinationStride = CVPixelBufferGetBytesPerRow(destination)
        guard destinationStride >= width * 4 else { return nil }
        for row in 0..<height {
            memcpy(destinationBase.advanced(by: row * destinationStride),
                   sourceBase.advanced(by: (y + row) * sourceStride + x * 4), width * 4)
        }
        CVBufferPropagateAttachments(source, destination)
        return destination
    }
}
