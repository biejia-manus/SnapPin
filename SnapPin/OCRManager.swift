import Cocoa
import Vision

// MARK: - OCRManager
// Wraps Apple Vision's VNRecognizeTextRequest for on-device, offline OCR.
// Supports Chinese (Simplified/Traditional) and English out of the box.

class OCRManager {

    static let shared = OCRManager()
    private init() {}

    // MARK: - Public API

    /// Recognize all text in the given image and return it as a single string.
    /// The result is delivered on the **main thread**.
    /// - Parameters:
    ///   - image: The NSImage to scan.
    ///   - completion: Called with the recognized text, or `nil` on failure.
    func recognizeText(from image: NSImage, completion: @escaping (String?) -> Void) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        let request = VNRecognizeTextRequest { request, error in
            guard error == nil,
                  let observations = request.results as? [VNRecognizedTextObservation],
                  !observations.isEmpty else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // Join each line's top candidate into a single string
            let text = observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")

            DispatchQueue.main.async {
                completion(text.isEmpty ? nil : text)
            }
        }

        // .accurate gives the best results; .fast is suitable for real-time use
        request.recognitionLevel = .accurate
        // Language priority: Simplified Chinese → Traditional Chinese → English
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        // Let Vision apply language-model corrections (spelling, context)
        request.usesLanguageCorrection = true

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("[OCRManager] Vision error: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    // MARK: - Convenience: recognize → copy to clipboard

    /// Recognize text from `image`, copy it to the system clipboard, and show
    /// a brief HUD notification anchored near `anchorRect` (in screen coordinates).
    /// - Parameters:
    ///   - image: Source image.
    ///   - anchorRect: Screen-coordinate rect used to position the HUD.
    func recognizeAndCopy(from image: NSImage, anchorRect: NSRect? = nil) {
        recognizeText(from: image) { text in
            if let text = text {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
                OCRResultHUD.show(text: text, near: anchorRect)
            } else {
                OCRResultHUD.showError(near: anchorRect)
            }
        }
    }
}

// MARK: - OCRResultHUD
// A lightweight floating panel that briefly shows the OCR result (or an error).
// Uses a light background with dark text for guaranteed contrast in any system appearance.

private class OCRResultHUD {

    private static var currentPanel: NSPanel?
    private static var dismissTimer: Timer?

    // Fixed palette — light card style, readable in both light and dark macOS modes
    private static let bgColor      = NSColor(calibratedRed: 0.98, green: 0.98, blue: 0.99, alpha: 0.97)
    private static let borderColor  = NSColor.black.withAlphaComponent(0.10)
    private static let titleColor   = NSColor(calibratedWhite: 0.10, alpha: 1)   // near-black
    private static let bodyColor    = NSColor(calibratedWhite: 0.30, alpha: 1)   // dark grey
    private static let dividerColor = NSColor.black.withAlphaComponent(0.10)

    // MARK: Success HUD

    static func show(text: String, near rect: NSRect?) {
        DispatchQueue.main.async {
            dismiss()

            let lineCount  = text.components(separatedBy: "\n").count
            let panelW: CGFloat = 340
            let lineH: CGFloat  = 18
            let padding: CGFloat = 16
            let headerH: CGFloat = 28
            let maxLines        = min(lineCount, 6)
            let panelH          = headerH + CGFloat(maxLines) * lineH + padding * 2

            let origin = hudOrigin(panelW: panelW, panelH: panelH, near: rect)
            let panel  = makePanel(frame: NSRect(x: origin.x, y: origin.y,
                                                  width: panelW, height: panelH))

            let cv = panel.contentView!

            // ── Header: icon + "Text Copied" label ──
            let iconView = NSImageView(frame: NSRect(x: padding, y: panelH - headerH - 4,
                                                     width: 20, height: 20))
            if let img = NSImage(systemSymbolName: "doc.on.clipboard.fill",
                                 accessibilityDescription: nil) {
                iconView.image = img
                iconView.contentTintColor = .systemGreen
            }
            cv.addSubview(iconView)

            let headerLabel = makeLabel(
                "Text Copied to Clipboard",
                font: .systemFont(ofSize: 13, weight: .semibold),
                color: titleColor,
                frame: NSRect(x: padding + 26, y: panelH - headerH - 2,
                              width: panelW - padding * 2 - 26, height: 20)
            )
            cv.addSubview(headerLabel)

            // ── Divider ──
            let divider = NSView(frame: NSRect(x: padding, y: panelH - headerH - 10,
                                               width: panelW - padding * 2, height: 1))
            divider.wantsLayer = true
            divider.layer?.backgroundColor = dividerColor.cgColor
            cv.addSubview(divider)

            // ── Preview lines ──
            let lines = text.components(separatedBy: "\n")
            let displayLines = Array(lines.prefix(6))
            let previewText = displayLines.joined(separator: "\n")
                + (lines.count > 6 ? "\n…" : "")

            let textField = NSTextField(frame: NSRect(
                x: padding, y: padding,
                width: panelW - padding * 2,
                height: CGFloat(maxLines) * lineH
            ))
            textField.stringValue   = previewText
            textField.font          = .monospacedSystemFont(ofSize: 11, weight: .regular)
            textField.textColor     = bodyColor
            textField.isBezeled     = false
            textField.drawsBackground = false
            textField.isEditable    = false
            textField.isSelectable  = false
            textField.lineBreakMode = .byTruncatingTail
            textField.maximumNumberOfLines = 6
            cv.addSubview(textField)

            panel.orderFrontRegardless()
            currentPanel = panel
            scheduleDismiss(after: 3.0)
        }
    }

    // MARK: Error HUD

    static func showError(near rect: NSRect?) {
        DispatchQueue.main.async {
            dismiss()

            let panelW: CGFloat = 280
            let panelH: CGFloat = 56
            let origin = hudOrigin(panelW: panelW, panelH: panelH, near: rect)
            let panel  = makePanel(frame: NSRect(x: origin.x, y: origin.y,
                                                  width: panelW, height: panelH))
            let cv = panel.contentView!

            let iconView = NSImageView(frame: NSRect(x: 16, y: (panelH - 20) / 2,
                                                     width: 20, height: 20))
            if let img = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                 accessibilityDescription: nil) {
                iconView.image = img
                iconView.contentTintColor = .systemOrange
            }
            cv.addSubview(iconView)

            let label = makeLabel(
                "No text recognized",
                font: .systemFont(ofSize: 13, weight: .medium),
                color: titleColor,
                frame: NSRect(x: 44, y: (panelH - 18) / 2,
                              width: panelW - 60, height: 18)
            )
            cv.addSubview(label)

            panel.orderFrontRegardless()
            currentPanel = panel
            scheduleDismiss(after: 2.0)
        }
    }

    // MARK: Dismiss

    static func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        currentPanel?.orderOut(nil)
        currentPanel?.close()
        currentPanel = nil
    }

    // MARK: Helpers

    private static func scheduleDismiss(after seconds: TimeInterval) {
        dismissTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            dismiss()
        }
    }

    private static func makePanel(frame: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let cv = NSView(frame: NSRect(origin: .zero, size: frame.size))
        cv.wantsLayer = true
        cv.layer?.backgroundColor = bgColor.cgColor
        cv.layer?.cornerRadius = 10
        cv.layer?.masksToBounds = true
        // Subtle border for definition against any background
        cv.layer?.borderColor = borderColor.cgColor
        cv.layer?.borderWidth = 0.5
        panel.contentView = cv
        return panel
    }

    private static func hudOrigin(panelW: CGFloat, panelH: CGFloat,
                                   near rect: NSRect?) -> NSPoint {
        // Prefer just below the anchor rect; fall back to bottom-right of main screen
        if let r = rect {
            let x = max(0, r.midX - panelW / 2)
            let y = r.minY - panelH - 8
            let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let clampedX = min(x, screen.maxX - panelW - 8)
            let clampedY = y < 0 ? r.maxY + 8 : y
            return NSPoint(x: clampedX, y: clampedY)
        }
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: screen.maxX - panelW - 24, y: 24)
    }

    private static func makeLabel(_ text: String, font: NSFont,
                                   color: NSColor, frame: NSRect) -> NSTextField {
        let l = NSTextField(frame: frame)
        l.stringValue       = text
        l.font              = font
        l.textColor         = color
        l.isBezeled         = false
        l.drawsBackground   = false
        l.isEditable        = false
        l.isSelectable      = false
        return l
    }
}
