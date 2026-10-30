import Cocoa
import Testing
@testable import SnapPin

/// Guards the F1 overlay contrast on white apps.
/// Thresholds follow WCAG 2.1 non-text contrast (at least 3:1).
@MainActor
@Suite(.serialized)
struct SelectionOverlayStyleTests {

    // MARK: Helpers

    /// WCAG 2.1 relative luminance of an sRGB color.
    private func luminance(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGFloat {
        func linear(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    private func contrast(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private struct RGB { let r, g, b: CGFloat }

    private func luminance(_ c: RGB) -> CGFloat { luminance(c.r, c.g, c.b) }

    private func whiteImage() throws -> CGImage {
        let provider = try #require(CGDataProvider(data: Data([255, 255, 255, 255]) as CFData))
        return try #require(CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: false,
                                    intent: .defaultIntent))
    }

    /// An overlay view over a fully white screen, the hardest case for the selection edge.
    private func whiteAppOverlay() throws -> OverlayView {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.screens.first)
        return OverlayView(frame: NSRect(x: 0, y: 0, width: 960, height: 600),
                           screenshotManager: ScreenshotManager(pinManager: PinManager()),
                           screen: screen, backgroundImage: try whiteImage())
    }

    private func mouse(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: [],
                                        timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                                        clickCount: 1, pressure: 1))
    }

    private func render(_ view: NSView) throws -> NSBitmapImageRep {
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }

    /// sRGB color of the bitmap pixel that covers a view point. Bitmap rows start at the top.
    private func pixel(_ bitmap: NSBitmapImageRep, _ view: NSView, _ x: CGFloat, _ y: CGFloat) throws -> RGB {
        let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
        let color = try #require(bitmap.colorAt(x: Int(x * scale), y: Int((view.bounds.height - y) * scale))?
            .usingColorSpace(.sRGB))
        return RGB(r: color.redComponent, g: color.greenComponent, b: color.blueComponent)
    }

    private func isClose(_ a: RGB, _ b: RGB, tolerance: CGFloat = 0.06) -> Bool {
        abs(a.r - b.r) <= tolerance && abs(a.g - b.g) <= tolerance && abs(a.b - b.b) <= tolerance
    }

    /// Expected sRGB color of white under the dim layer.
    /// AppKit blends in the bitmap color space (Generic RGB offscreen, the display space on screen),
    /// so the blended gray is converted from that space to sRGB.
    private func expectedDimmedWhite(in bitmap: NSBitmapImageRep) throws -> RGB {
        let d = 1 - SelectionOverlayStyle.dimAlpha
        let c = try #require(NSColor(colorSpace: bitmap.colorSpace, components: [d, d, d, 1], count: 4)
            .usingColorSpace(.sRGB))
        return RGB(r: c.redComponent, g: c.greenComponent, b: c.blueComponent)
    }

    // MARK: Style values

    @Test func dimmedWhiteContrastsWithSelectedWhite() {
        let dimmed = 1 - SelectionOverlayStyle.dimAlpha
        #expect(contrast(luminance(1, 1, 1), luminance(dimmed, dimmed, dimmed)) >= 3.0)
        // The dimmed area must stay readable enough to aim the selection.
        #expect(SelectionOverlayStyle.dimAlpha <= 0.6)
    }

    @Test func borderContrastsWithWhiteAndDarkContent() throws {
        let c = try #require(SelectionOverlayStyle.borderColor.usingColorSpace(.sRGB))
        let border = luminance(c.redComponent, c.greenComponent, c.blueComponent)
        #expect(contrast(border, luminance(1, 1, 1)) >= 3.0)
        #expect(contrast(border, luminance(0.12, 0.12, 0.12)) >= 3.0)
    }

    @Test func borderAndHaloStayOutsideSelection() {
        let selection = NSRect(x: 100.5, y: 80, width: 300, height: 200.25)
        let w = SelectionOverlayStyle.borderWidth
        let hw = SelectionOverlayStyle.borderHaloWidth
        let border = SelectionOverlayStyle.borderStrokeRect(for: selection)
        let halo = SelectionOverlayStyle.haloStrokeRect(for: selection)
        // Inner edge of the accent stroke is the selection edge.
        #expect(border.insetBy(dx: w / 2, dy: w / 2) == selection)
        // Inner edge of the halo is the outer edge of the accent stroke.
        #expect(halo.insetBy(dx: hw / 2, dy: hw / 2) == border.insetBy(dx: -w / 2, dy: -w / 2))
    }

    // MARK: Rendered overlay

    @Test func selectionEdgeIsVisibleOnWhiteApp() throws {
        let view = try whiteAppOverlay()
        view.mouseDown(with: try mouse(.leftMouseDown, 250, 120))
        view.mouseUp(with: try mouse(.leftMouseUp, 700, 470))
        #expect(view.hasSelection)
        let bitmap = try render(view)

        // y = 200 avoids the resize handles, the size label and the toolbar.
        let inside = try pixel(bitmap, view, 698, 200)
        let outside = try pixel(bitmap, view, 706, 200)
        #expect(isClose(inside, RGB(r: 1, g: 1, b: 1), tolerance: 0.02))
        #expect(isClose(outside, try expectedDimmedWhite(in: bitmap), tolerance: 0.02))
        #expect(contrast(luminance(inside), luminance(outside)) >= 3.0)

        // The accent border is drawn just outside every edge of the selection.
        let c = try #require(SelectionOverlayStyle.borderColor.usingColorSpace(.sRGB))
        let accent = RGB(r: c.redComponent, g: c.greenComponent, b: c.blueComponent)
        for (x, y) in [(701.0, 200.0), (249.0, 200.0), (400.0, 471.0), (400.0, 119.0)] {
            let edge = try pixel(bitmap, view, x, y)
            #expect(isClose(edge, accent), "edge pixel at (\(x), \(y)) is \(edge)")
        }
    }

    @Test func crosshairIsVisibleOnWhiteApp() throws {
        let view = try whiteAppOverlay()
        // A half-point position puts the 1 pt line exactly on one pixel row.
        view.mouseMoved(with: try mouse(.mouseMoved, 420.5, 330.5))
        let bitmap = try render(view)

        let dimmed = luminance(try pixel(bitmap, view, 100, 100))
        let row = try stride(from: 0.5, to: 300.0, by: 1.0).map { luminance(try pixel(bitmap, view, $0, 330.75)) }
        // Dark dashes must stand out from the dimmed white area, and so must light dashes.
        #expect(contrast(try #require(row.min()), dimmed) >= 2.0)
        #expect(contrast(try #require(row.max()), dimmed) >= 2.0)
    }
}
