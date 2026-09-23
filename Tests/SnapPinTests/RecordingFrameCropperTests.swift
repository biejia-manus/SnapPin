import Cocoa
import CoreVideo
import Testing
@testable import SnapPin

struct RecordingFrameCropperTests {
    @Test(arguments: [CGPoint.zero, CGPoint(x: -1920, y: 180), CGPoint(x: 1512, y: -200),
                      CGPoint(x: 120, y: 982), CGPoint(x: -300, y: -1080)])
    func displayOriginDoesNotChangeCrop(origin: CGPoint) {
        let screen = CGRect(origin: origin, size: CGSize(width: 1920, height: 1080))
        let selection = CGRect(x: origin.x + 120, y: origin.y + 300, width: 400, height: 200)
        #expect(RecordingFrameCropper.pixelRect(for: selection, on: screen, pixelWidth: 3840, pixelHeight: 2160)
            == CGRect(x: 240, y: 1160, width: 800, height: 400))
    }

    @Test func scalesAxesIndependentlyAndRoundsOutward() {
        let screen = CGRect(x: -100, y: 50, width: 100, height: 100)
        let region = CGRect(x: -89.5, y: 70.25, width: 20, height: 30)
        #expect(RecordingFrameCropper.pixelRect(for: region, on: screen, pixelWidth: 150, pixelHeight: 200)
            == CGRect(x: 15, y: 99, width: 31, height: 61))
    }

    @Test func clipsPartiallyOutsideSelection() {
        let screen = CGRect(x: -1920, y: 180, width: 1920, height: 1080)
        let region = CGRect(x: -1930, y: 170, width: 40, height: 40)
        #expect(RecordingFrameCropper.pixelRect(for: region, on: screen, pixelWidth: 3840, pixelHeight: 2160)
            == CGRect(x: 0, y: 2100, width: 60, height: 60))
        #expect(RecordingFrameCropper.pixelRect(for: screen, on: screen, pixelWidth: 3840, pixelHeight: 2160)
            == CGRect(x: 0, y: 0, width: 3840, height: 2160))
    }

    @Test func rejectsInvalidOrDisjointSelection() {
        let screen = CGRect(x: 0, y: 0, width: 100, height: 100)
        for region in [CGRect.zero, CGRect(x: 100, y: 0, width: 20, height: 20),
                       CGRect(x: -30, y: 0, width: 20, height: 20),
                       CGRect(x: 0, y: CGFloat.nan, width: 20, height: 20), CGRect.infinite] {
            #expect(RecordingFrameCropper.pixelRect(for: region, on: screen, pixelWidth: 200, pixelHeight: 200) == nil)
        }
        #expect(RecordingFrameCropper.pixelRect(for: screen, on: .zero, pixelWidth: 200, pixelHeight: 200) == nil)
        #expect(RecordingFrameCropper.pixelRect(for: screen, on: screen, pixelWidth: 0, pixelHeight: 200) == nil)
    }

    @Test func copiesCorrectRowsWithPaddedStrideAndExternalDisplayOrigin() throws {
        let source = try makeBuffer()
        let screen = CGRect(x: -500, y: 200, width: 4, height: 4)
        let output = try #require(RecordingFrameCropper.crop(source, to: CGRect(x: -499, y: 201, width: 2, height: 2), on: screen))
        #expect(CVPixelBufferGetWidth(output) == 2)
        #expect(CVPixelBufferGetHeight(output) == 2)
        #expect(try blueValues(output) == [11, 12, 21, 22])
        #expect(CVPixelBufferLockBaseAddress(source, .readOnly) == kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
        #expect(CVPixelBufferLockBaseAddress(output, .readOnly) == kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(output, .readOnly) }
        #expect(CVPixelBufferGetBaseAddress(source) != CVPixelBufferGetBaseAddress(output))
    }

    @Test func outputDoesNotAliasReusedCaptureMemory() throws {
        let source = try makeBuffer()
        let screen = CGRect(x: 0, y: 0, width: 4, height: 4)
        let output = try #require(RecordingFrameCropper.crop(source, to: screen, on: screen))
        #expect(CVPixelBufferLockBaseAddress(source, []) == kCVReturnSuccess)
        let pointer = try #require(CVPixelBufferGetBaseAddress(source))
        memset(pointer, 0, CVPixelBufferGetBytesPerRow(source) * CVPixelBufferGetHeight(source))
        CVPixelBufferUnlockBaseAddress(source, [])
        #expect(try blueValues(output) == [0, 1, 2, 3, 10, 11, 12, 13, 20, 21, 22, 23, 30, 31, 32, 33])
    }

    @Test func survivesSourceReleaseAndDeferredCoreImageRead() throws {
        let output: CVPixelBuffer = try autoreleasepool {
            let source = try makeBuffer()
            let screen = CGRect(x: 1200, y: -700, width: 4, height: 4)
            return try #require(RecordingFrameCropper.crop(source,
                to: CGRect(x: 1201, y: -699, width: 2, height: 2), on: screen))
        }
        let context = CIContext(options: [.useSoftwareRenderer: true])
        // Mirrors the asynchronous Core Image path shown in the user's crash report.
        for _ in 0..<50 {
            let deferredImage = CIImage(cvPixelBuffer: output)
            let rendered = try #require(context.createCGImage(deferredImage, from: deferredImage.extent))
            #expect(rendered.width == 2)
            #expect(rendered.height == 2)
            #expect(try blueValues(output) == [11, 12, 21, 22])
        }
    }

    @Test func preservesOnePixelAtEveryEdge() throws {
        let source = try makeBuffer()
        let screen = CGRect(x: -4, y: -4, width: 4, height: 4)
        for (point, value) in [(CGPoint(x: -4, y: -1), UInt8(0)), (CGPoint(x: -1, y: -1), UInt8(3)),
                               (CGPoint(x: -4, y: -4), UInt8(30)), (CGPoint(x: -1, y: -4), UInt8(33))] {
            let output = try #require(RecordingFrameCropper.crop(source,
                to: CGRect(origin: point, size: CGSize(width: 1, height: 1)), on: screen))
            #expect(try blueValues(output) == [value])
        }
    }

    private func makeBuffer() throws -> CVPixelBuffer {
        var allocation: CVPixelBuffer?
        let attributes: [CFString: Any] = [kCVPixelBufferBytesPerRowAlignmentKey: 64,
                                          kCVPixelBufferCGImageCompatibilityKey: true]
        #expect(CVPixelBufferCreate(kCFAllocatorDefault, 4, 4, kCVPixelFormatType_32BGRA,
                                    attributes as CFDictionary, &allocation) == kCVReturnSuccess)
        let buffer = try #require(allocation)
        #expect(CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let base = try #require(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        for y in 0..<4 {
            for x in 0..<4 {
                let offset = y * CVPixelBufferGetBytesPerRow(buffer) + x * 4
                base[offset] = UInt8(y * 10 + x)
                base[offset + 1] = 40
                base[offset + 2] = 80
                base[offset + 3] = 255
            }
        }
        return buffer
    }

    private func blueValues(_ buffer: CVPixelBuffer) throws -> [UInt8] {
        #expect(CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = try #require(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        return (0..<CVPixelBufferGetHeight(buffer)).flatMap { y in
            (0..<CVPixelBufferGetWidth(buffer)).map { x in base[y * CVPixelBufferGetBytesPerRow(buffer) + x * 4] }
        }
    }
}
