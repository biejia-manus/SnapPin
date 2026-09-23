import Cocoa
import Testing
@testable import SnapPin

@MainActor
@Suite(.serialized)
struct ColorPickerInteractionTests {
    private func fixture(image: CGImage? = nil) throws -> (ScreenshotManager, OverlayView) {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.screens.first)
        let manager = ScreenshotManager(pinManager: PinManager())
        let view = OverlayView(frame: NSRect(x: 0, y: 0, width: 800, height: 600),
                               screenshotManager: manager, screen: screen, backgroundImage: image)
        return (manager, view)
    }

    private func key(_ code: UInt16, flags: NSEvent.ModifierFlags = [], characters: String = "") throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                     timestamp: 0, windowNumber: 0, context: nil,
                                     characters: characters, charactersIgnoringModifiers: characters,
                                     isARepeat: false, keyCode: code))
    }

    @Test func lockRetainsColorUntilNextPick() throws {
        let (manager, view) = try fixture()
        manager.beginColorPicking(from: view)
        #expect(manager.isPickingColor)
        #expect(manager.pickedColor == nil)
        let color = ScreenColor(red: 12, green: 34, blue: 56)
        manager.updatePickedColor(color)
        #expect(manager.handleColorPickerKeyEvent(try key(36)))
        #expect(!manager.isPickingColor)
        #expect(manager.pickedColor == color)
        manager.updatePickedColor(ScreenColor(red: 255, green: 255, blue: 255))
        #expect(manager.pickedColor == color)
        manager.beginColorPicking(from: view)
        #expect(manager.isPickingColor)
        #expect(manager.pickedColor == nil)
        manager.endColorPicking()
    }

    @Test func bothFormatsCopyWithoutUsingUsersClipboard() throws {
        let (manager, view) = try fixture()
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        manager.beginColorPicking(from: view)
        manager.updatePickedColor(ScreenColor(red: 4, green: 128, blue: 255))
        manager.copyPickedColor(.hex, to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "#0480FF")
        #expect(!manager.isPickingColor)
        manager.copyPickedColor(.rgba, to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "rgba(4, 128, 255, 1)")
        manager.endColorPicking()
    }

    @Test func escapeExitsPickerBeforeScreenshotCancellation() throws {
        let (manager, view) = try fixture()
        let escape = try key(53)
        #expect(!manager.handleColorPickerKeyEvent(escape))
        manager.beginColorPicking(from: view)
        manager.updatePickedColor(ScreenColor(red: 1, green: 2, blue: 3))
        #expect(manager.handleColorPickerKeyEvent(escape))
        #expect(manager.pickedColor == nil)
        #expect(!manager.isPickingColor)
        #expect(!manager.handleColorPickerKeyEvent(escape))
        #expect(view.subviews.compactMap { $0 as? ColorPickerResultView }.isEmpty)
    }

    @Test func noSampleNeverCopiesAFakeColor() throws {
        let (manager, view) = try fixture()
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("untouched", forType: .string)
        manager.beginColorPicking(from: view)
        manager.copyPickedColor(.hex, to: pasteboard)
        manager.lockPickedColor()
        #expect(manager.isPickingColor)
        #expect(pasteboard.string(forType: .string) == "untouched")
        // Even with no sample, shortcuts must not fall through to screenshot copy.
        #expect(manager.handleColorPickerKeyEvent(try key(8, flags: .command, characters: "c")))
        #expect(manager.handleColorPickerKeyEvent(try key(76)))
        #expect(!manager.handleColorPickerKeyEvent(try key(0, characters: "a")))
        #expect(!manager.handleColorPickerKeyEvent(try key(120, flags: .function))) // F2 stays available.
        manager.endColorPicking()
    }

    @Test func samplingClickDoesNotCreateSelectionAndMissingImageIsSafe() throws {
        let (manager, view) = try fixture()
        manager.beginColorPicking(from: view)
        // No screen capture is started in this fixture; enable this detached view directly.
        view.setColorPicking(true)
        let down = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 300, y: 300),
                                                   modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                   context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        view.mouseDown(with: down)
        #expect(!view.hasSelection)
        #expect(manager.pickedColor == nil)
        #expect(manager.isPickingColor)
        manager.endColorPicking()
        view.setColorPicking(false)
    }

    @Test func toolbarPickingPreservesSelectionAndStaysOnScreen() throws {
        let bytes: [UInt8] = [36, 128, 208, 255]
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let image = try #require(CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let (manager, view) = try fixture(image: image)
        func mouse(_ type: NSEvent.EventType, _ point: NSPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        view.mouseDown(with: try mouse(.leftMouseDown, NSPoint(x: 0, y: 0)))
        view.mouseUp(with: try mouse(.leftMouseUp, NSPoint(x: 799, y: 599)))
        #expect(view.hasSelection)
        let toolbar = try #require(view.subviews.first)
        #expect(view.bounds.contains(toolbar.frame))
        let picker = try #require(toolbar.subviews.compactMap { $0 as? NSButton }
            .first { $0.action == NSSelectorFromString("toolbarColorPicker") })
        picker.performClick(nil)
        view.setColorPicking(true) // The fixture view is not registered as a real capture window.
        let panel = try #require(view.subviews.compactMap { $0 as? ColorPickerResultView }.first)
        #expect(view.bounds.contains(panel.frame))
        #expect(!panel.frame.intersects(toolbar.frame))
        view.mouseMoved(with: try mouse(.mouseMoved, NSPoint(x: 280, y: 300)))
        #expect(manager.pickedColor?.hex == "#2480D0")

        // Optional deterministic AppKit render for visual QA; no desktop capture or permissions needed.
        if let path = ProcessInfo.processInfo.environment["SNAPPIN_PREVIEW_PATH"] {
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path))
        }

        view.mouseDown(with: try mouse(.leftMouseDown, NSPoint(x: 280, y: 300)))
        view.mouseUp(with: try mouse(.leftMouseUp, NSPoint(x: 280, y: 300)))
        #expect(view.hasSelection)
        #expect(!manager.isPickingColor)
        #expect(manager.pickedColor?.rgba == "rgba(36, 128, 208, 1)")
        #expect(manager.handleColorPickerKeyEvent(try key(53)))
        #expect(view.hasSelection)
        view.setColorPicking(false)
    }

    @Test func resultPanelHasSeparateCopyActionsAndUnavailableState() throws {
        _ = NSApplication.shared
        let panel = ColorPickerResultView()
        let buttons = panel.subviews.compactMap { $0 as? NSButton }
        #expect(buttons.count == 2)
        #expect(buttons.allSatisfy { !$0.isEnabled })
        let color = ScreenColor(red: 255, green: 255, blue: 255)
        panel.update(color: color, isPicking: false)
        #expect(buttons.allSatisfy { $0.isEnabled })
        let labels = panel.subviews.compactMap { $0 as? NSTextField }
        #expect(labels.contains { $0.stringValue == color.hex })
        #expect(labels.contains { $0.stringValue == color.rgba })
        for label in labels where label.stringValue == color.hex || label.stringValue == color.rgba {
            let width = (label.stringValue as NSString).size(withAttributes: [.font: try #require(label.font)]).width
            #expect(width + 4 <= label.frame.width)
        }
        var formats: [ScreenColorFormat] = []
        panel.onCopy = { formats.append($0) }
        for button in buttons { button.performClick(nil) }
        #expect(formats == [.hex, .rgba])
        panel.update(color: nil, isPicking: true)
        #expect(buttons.allSatisfy { !$0.isEnabled })
    }
}
