import Cocoa

/// Lives inside the shielding-level overlay so it remains visible above the capture UI.
final class ColorPickerResultView: NSView {
    private let swatch = NSView()
    private let hexLabel = NSTextField(labelWithString: "—")
    private let rgbaLabel = NSTextField(labelWithString: "—")
    private let hintLabel = NSTextField(labelWithString: "")
    private let hexCopyButton = NSButton(title: "Copy", target: nil, action: nil)
    private let rgbaCopyButton = NSButton(title: "Copy", target: nil, action: nil)
    var onCopy: ((ScreenColorFormat) -> Void)?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 344, height: 112))
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.97).cgColor
        layer?.cornerRadius = 8
        layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        layer?.borderWidth = 0.5

        let title = NSTextField(labelWithString: "Screen color · sRGB")
        title.frame = NSRect(x: 12, y: 87, width: 310, height: 17)
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.textColor = .white
        addSubview(title)

        swatch.frame = NSRect(x: 12, y: 36, width: 28, height: 38)
        swatch.wantsLayer = true
        swatch.layer?.cornerRadius = 4
        swatch.layer?.borderWidth = 1
        swatch.layer?.borderColor = NSColor.white.withAlphaComponent(0.4).cgColor
        addSubview(swatch)

        for (name, label, button, y) in [("HEX", hexLabel, hexCopyButton, CGFloat(59)),
                                        ("RGBA", rgbaLabel, rgbaCopyButton, CGFloat(32))] {
            let caption = NSTextField(labelWithString: name)
            caption.frame = NSRect(x: 49, y: y, width: 34, height: 17)
            caption.font = .systemFont(ofSize: 10, weight: .medium)
            caption.textColor = NSColor(white: 0.65, alpha: 1)
            addSubview(caption)

            label.frame = NSRect(x: 86, y: y, width: 195, height: 17)
            label.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
            label.textColor = .white
            label.setAccessibilityLabel(name)
            addSubview(label)

            button.frame = NSRect(x: 285, y: y - 3, width: 48, height: 24)
            button.bezelStyle = .inline
            button.contentTintColor = .white
            button.font = .systemFont(ofSize: 11, weight: .medium)
            button.target = self
            button.action = name == "HEX" ? #selector(copyHex) : #selector(copyRGBA)
            button.setAccessibilityLabel("Copy \(name) color")
            addSubview(button)
        }

        hintLabel.frame = NSRect(x: 12, y: 7, width: 322, height: 15)
        hintLabel.font = .systemFont(ofSize: 10)
        hintLabel.textColor = NSColor(white: 0.75, alpha: 1)
        addSubview(hintLabel)
        update(color: nil, isPicking: true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(color: ScreenColor?, isPicking: Bool) {
        hexLabel.stringValue = color?.hex ?? "—"
        rgbaLabel.stringValue = color?.rgba ?? "—"
        swatch.layer?.backgroundColor = color?.nsColor.cgColor ?? NSColor.clear.cgColor
        hexCopyButton.isEnabled = color != nil
        rgbaCopyButton.isEnabled = color != nil
        if color == nil {
            hintLabel.stringValue = "Move over captured screen · Esc to exit"
        } else {
            hintLabel.stringValue = isPicking
                ? "Move mouse · Click to lock · Esc to exit"
                : "Locked · ⌘C HEX / ⇧⌘C RGBA · Eyedropper to pick again"
        }
    }

    func showCopied(_ format: ScreenColorFormat) {
        hintLabel.stringValue = "\(format == .hex ? "HEX" : "RGBA") copied · Eyedropper to pick again"
    }

    @objc private func copyHex() { onCopy?(.hex) }
    @objc private func copyRGBA() { onCopy?(.rgba) }
}
