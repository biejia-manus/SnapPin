import Cocoa
import Testing
@testable import SnapPin

struct ScreenColorSamplerTests {
    @Test func cssFormats() {
        let color = ScreenColor(red: 0, green: 15, blue: 255)
        #expect(color.hex == "#000FFF")
        #expect(color.rgba == "rgba(0, 15, 255, 1)")
        #expect(ScreenColorFormat.hex.string(for: color) == color.hex)
        #expect(ScreenColorFormat.rgba.string(for: color) == color.rgba)
        #expect(ScreenColor(red: 255, green: 255, blue: 255).hex == "#FFFFFF")
        #expect(ScreenColor(red: 0, green: 0, blue: 0).rgba == "rgba(0, 0, 0, 1)")
    }

    @Test func previewUsesSRGBComponents() {
        let color = ScreenColor(red: 23, green: 128, blue: 240).nsColor
        #expect(abs(color.redComponent - 23.0 / 255) < 0.00001)
        #expect(abs(color.greenComponent - 128.0 / 255) < 0.00001)
        #expect(abs(color.blueComponent - 240.0 / 255) < 0.00001)
        #expect(color.alphaComponent == 1)
    }

    @Test func allFourCornersAndYAxisFlip() {
        let bounds = NSRect(x: 0, y: 0, width: 100, height: 50)
        for (point, expected) in [
            (NSPoint(x: 0, y: 0), CGRect(x: 0, y: 49, width: 1, height: 1)),
            (NSPoint(x: 99.99, y: 0), CGRect(x: 99, y: 49, width: 1, height: 1)),
            (NSPoint(x: 0, y: 49.99), CGRect(x: 0, y: 0, width: 1, height: 1)),
            (NSPoint(x: 99.99, y: 49.99), CGRect(x: 99, y: 0, width: 1, height: 1))
        ] {
            #expect(ScreenColorSampler.pixelRect(at: point, in: bounds, imageWidth: 100, imageHeight: 50) == expected)
        }
    }

    @Test func retinaCoordinates() {
        let bounds = NSRect(x: 0, y: 0, width: 100, height: 50)
        #expect(ScreenColorSampler.pixelRect(at: NSPoint(x: 12.75, y: 20.25), in: bounds,
                                             imageWidth: 200, imageHeight: 100) == CGRect(x: 25, y: 59, width: 1, height: 1))
    }

    @Test func nonIntegerAndIndependentScales() {
        let bounds = NSRect(x: 0, y: 0, width: 100, height: 50)
        #expect(ScreenColorSampler.pixelRect(at: NSPoint(x: 40, y: 10), in: bounds,
                                             imageWidth: 150, imageHeight: 125) == CGRect(x: 60, y: 99, width: 1, height: 1))
    }

    @Test func offsetDisplayBounds() {
        let bounds = NSRect(x: -1920, y: 240, width: 1920, height: 1080)
        #expect(ScreenColorSampler.pixelRect(at: NSPoint(x: -1910, y: 250), in: bounds,
                                             imageWidth: 3840, imageHeight: 2160) == CGRect(x: 20, y: 2139, width: 1, height: 1))
    }

    @Test func outsideAndInvalidCoordinatesAreRejected() {
        let bounds = NSRect(x: 0, y: 0, width: 100, height: 50)
        for point in [NSPoint(x: -0.01, y: 1), NSPoint(x: 1, y: -0.01),
                      NSPoint(x: 100, y: 1), NSPoint(x: 1, y: 50),
                      NSPoint(x: CGFloat.nan, y: 1), NSPoint(x: 1, y: CGFloat.infinity)] {
            #expect(ScreenColorSampler.pixelRect(at: point, in: bounds, imageWidth: 200, imageHeight: 100) == nil)
        }
        #expect(ScreenColorSampler.pixelRect(at: .zero, in: .zero, imageWidth: 200, imageHeight: 100) == nil)
        #expect(ScreenColorSampler.pixelRect(at: .zero, in: bounds, imageWidth: 0, imageHeight: 100) == nil)
    }

    @Test func samplesExactPixelsWithoutInterpolation() throws {
        // CGImage data rows are top-to-bottom: red/green, then blue/white.
        let image = try makeImage(bytes: [255, 0, 0, 255, 0, 255, 0, 255,
                                          0, 0, 255, 255, 255, 255, 255, 255], width: 2, height: 2)
        let bounds = NSRect(x: 0, y: 0, width: 1, height: 1)
        #expect(ScreenColorSampler.sample(at: NSPoint(x: 0.25, y: 0.75), in: bounds, image: image)?.hex == "#FF0000")
        #expect(ScreenColorSampler.sample(at: NSPoint(x: 0.75, y: 0.75), in: bounds, image: image)?.hex == "#00FF00")
        #expect(ScreenColorSampler.sample(at: NSPoint(x: 0.25, y: 0.25), in: bounds, image: image)?.hex == "#0000FF")
        #expect(ScreenColorSampler.sample(at: NSPoint(x: 0.75, y: 0.25), in: bounds, image: image)?.hex == "#FFFFFF")
        #expect(ScreenColorSampler.sample(at: NSPoint(x: 1, y: 1), in: bounds, image: image) == nil)
    }

    @Test func sourceByteOrderIsNotAssumed() throws {
        // BGRA memory, a common capture layout.
        let image = try makeImage(bytes: [51, 34, 17, 255], width: 1, height: 1,
                                  bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
        #expect(ScreenColorSampler.sample(at: .zero, in: NSRect(x: 0, y: 0, width: 1, height: 1), image: image)?.hex == "#112233")
    }

    @Test func displayP3IsConvertedToSRGB() throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let image = try makeImage(bytes: [160, 110, 80, 255], width: 1, height: 1, colorSpace: space)
        let expected = try #require(NSColor(displayP3Red: 160.0 / 255, green: 110.0 / 255, blue: 80.0 / 255, alpha: 1)
            .usingColorSpace(.sRGB))
        let sampled = try #require(ScreenColorSampler.sample(at: .zero, in: NSRect(x: 0, y: 0, width: 1, height: 1), image: image))
        #expect(abs(Double(sampled.red) - Double(expected.redComponent * 255)) <= 1)
        #expect(abs(Double(sampled.green) - Double(expected.greenComponent * 255)) <= 1)
        #expect(abs(Double(sampled.blue) - Double(expected.blueComponent * 255)) <= 1)
    }

    private func makeImage(bytes: [UInt8], width: Int, height: Int,
                           colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!,
                           bitmapInfo: UInt32 = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) throws -> CGImage {
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        return try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
}
