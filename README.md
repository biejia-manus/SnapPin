# SnapPin

A lightweight screenshot and pin tool for macOS, inspired by Snipaste.

> **Built entirely by [Manus AI](https://manus.im).** Want to build your own macOS app like this? Try [Manus Desktop](https://manus.im/desktop)!

## Features

- **F1** — Take a screenshot (freeze screen, drag to select area); press F1 again to pin the selection
- **F2** — After selecting a region with F1, start recording; press F2 again to stop and save
- **F3** — Extract text from the selected screenshot (OCR)
- **Cmd+C / Enter** — Copy screenshot to clipboard and close (after selection)
- **Esc** — Cancel screenshot or close pinned image

### Screen Recording
- **Export Formats** — Save recordings as MP4 video or GIF animation
- **Recording Indicator** — A red border clearly shows the area being recorded
- **Customizable Hotkey** — Change the default F2 hotkey in Settings

### Screenshot Editing
- **Drag handles** to resize the selection area
- **Drag inside** to move the selection
- **Shift + Arrow Keys** to nudge selection by 1px
- **Cmd+Z** to undo the last annotation

### Annotation Tools
- **Arrow** — Draw arrows to highlight areas
- **Rectangle** — Draw rectangles to frame content
- **Text** — Add text labels with full IME support (Chinese, Japanese, etc.)
- **Mosaic** — Brush to pixelate sensitive information
- **Annotation Palette** — Choose annotation color (red, orange, yellow, green, blue, purple, white, black)

### Screen Color Picker

After selecting a screenshot region, click the **eyedropper** in the bottom toolbar. Move the mouse over any captured display to preview the pixel color, then click to lock it without changing the selection. The result panel shows a color swatch, **HEX** (`#RRGGBB`), and **RGBA** (`rgba(R, G, B, 1)`), with separate Copy buttons.

While the color panel is open, **Cmd+C** copies HEX, **Shift+Cmd+C** copies RGBA, and **Enter** locks the current sample instead of copying the screenshot. Click the eyedropper again after locking to pick another color. **Esc** exits the color tool and preserves the screenshot selection; a second Esc cancels the screenshot. Selecting an annotation tool also exits the color tool.

Colors are read from the original frozen screenshot, not from the dimming overlay, toolbar, or annotations. Sampling respects each display's actual image resolution and converts its color profile to 8-bit **sRGB**. Screen pixels are already composited, so alpha is **1**; this does not recover an application's original layer opacity.

### Pinned Image
- **Pinch-to-zoom** (Trackpad) or **Scroll-to-zoom** (Mouse wheel) to zoom in/out
- **Drag** to move
- **Cmd+C** to copy to clipboard
- **Esc** to close

### Settings
- Customizable hotkeys for screenshot, record, and OCR actions
- Permission status check and quick access to System Settings
- Accessible from the menu bar icon

## Installation

### Download
Download a `.dmg` or `.zip` from [GitHub Releases](https://github.com/biejia-manus/SnapPin/releases). Quit any running copy of SnapPin, then open the DMG (or extract the ZIP) and move `SnapPin.app` to your Applications folder.

The v1.3.0 prebuilt packages target **Apple Silicon (arm64), macOS 14+**. They are ad-hoc signed, not Apple-notarized. macOS may show a security warning; only approve the app if you trust this repository. SHA-256 checksums are provided with the release. Intel Mac users can build from source; no Intel prebuilt package is included in this release.

### Build from Source
Requires Swift 5.9+ and macOS 14+.

```bash
git clone https://github.com/biejia-manus/SnapPin.git
cd SnapPin
swift build
bash build_app.sh
open SnapPin.app
```

For an optimized app and a versioned DMG, run `CONFIGURATION=release bash build_app.sh`, then `bash create_dmg.sh`. Both scripts read the application version from `SnapPin/Info.plist` (the DMG script reads the bundled copy).

Run the color picker and recording regression tests with `swift test` (tests require Swift 6+ for Swift Testing). If a Command Line Tools-only installation cannot locate the Testing macro plugin, use:

```bash
swift test --disable-xctest --enable-swift-testing \
  -Xswiftc -plugin-path \
  -Xswiftc "$(dirname "$(xcrun --find swiftc)")/../lib/swift/host/plugins/testing"
```

## Permissions

SnapPin requires the following macOS permissions:

- **Screen Recording** — To capture screenshots and record screen
- **Accessibility** — For global hotkeys (optional, improves reliability)

On first launch, a Settings window will guide you through granting these permissions.

## Tech Stack

- Swift + AppKit (native macOS)
- ScreenCaptureKit (screen capture and recording)
- AVFoundation (MP4/GIF encoding)
- HotKey (Carbon-based global hotkeys via [soffes/HotKey](https://github.com/soffes/HotKey))
- Core Graphics (annotation rendering)

## Credits

This project was built entirely by [Manus AI](https://manus.im), an autonomous AI agent. If you'd like to create your own macOS applications with AI assistance, check out [Manus Desktop](https://manus.im/desktop).

## License

MIT
