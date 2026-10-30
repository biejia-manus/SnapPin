import Cocoa

/// Visual style of the F1 selection overlay.
///
/// The values keep the selection edge visible on both white and dark apps.
/// Contrast targets follow WCAG 2.1 non-text contrast (at least 3:1).
enum SelectionOverlayStyle {

    // MARK: Dim layer

    /// Black dim over the area outside the selection.
    /// 0.5 turns pure white into about #808080: about 3.9:1 against selected white.
    /// The old value 0.3 gave about 2.1:1, so white apps looked almost undimmed.
    static let dimAlpha: CGFloat = 0.5
    static let dimColor = NSColor.black.withAlphaComponent(dimAlpha)

    // MARK: Selection border

    /// Accent border (#0A84FF). It contrasts with white (about 3.6:1) and dark content.
    static let borderColor = NSColor(srgbRed: 10.0 / 255.0, green: 132.0 / 255.0, blue: 1.0, alpha: 1.0)
    static let borderWidth: CGFloat = 2.0

    /// Thin dark line outside the accent border.
    /// It separates the border from the dimmed area, which has a similar luminance.
    static let borderHaloColor = NSColor.black.withAlphaComponent(0.35)
    static let borderHaloWidth: CGFloat = 1.0

    /// Rect to stroke with `borderWidth`.
    /// The stroke sits fully outside the selection, so it never hides captured pixels.
    static func borderStrokeRect(for selection: NSRect) -> NSRect {
        selection.insetBy(dx: -borderWidth / 2, dy: -borderWidth / 2)
    }

    /// Rect to stroke with `borderHaloWidth`, directly outside the accent border.
    static func haloStrokeRect(for selection: NSRect) -> NSRect {
        let offset = borderWidth + borderHaloWidth / 2
        return selection.insetBy(dx: -offset, dy: -offset)
    }

    // MARK: Resize handles

    static let handleFillColor = borderColor
    static let handleStrokeColor = NSColor.white
    static let handleStrokeWidth: CGFloat = 1.0

    // MARK: Crosshair

    /// The crosshair alternates dark and light dashes.
    /// Dark dashes show on light apps, and light dashes show on dark apps.
    static let crosshairDarkColor = NSColor.black.withAlphaComponent(0.55)
    static let crosshairLightColor = NSColor.white.withAlphaComponent(0.9)
    static let crosshairLineWidth: CGFloat = 1.0
    static let crosshairDashLength: CGFloat = 5.0
}
