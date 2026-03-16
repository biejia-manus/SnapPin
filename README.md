# SnapPin

A lightweight screenshot and pin tool for macOS, inspired by Snipaste.

> **Built entirely by [Manus AI](https://manus.im).** Want to build your own macOS app like this? Try [Manus Desktop](https://manus.im/desktop)!

## Features

- **F1** — Take a screenshot (freeze screen, drag to select area)
- **F3** — Pin the screenshot to screen (after selection)
- **Cmd+C / Enter** — Copy screenshot to clipboard and close (after selection)
- **Esc** — Cancel screenshot or close pinned image

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
- **Color Picker** — Choose annotation color (red, orange, yellow, green, blue, purple, white, black)

### Pinned Image
- **Scroll** to zoom in/out
- **Drag** to move
- **Cmd+C** to copy to clipboard
- **Esc** to close

### Settings
- Customizable hotkeys for screenshot and pin actions
- Permission status check and quick access to System Settings
- Accessible from the menu bar icon

## Installation

### Download DMG
Download the latest `.dmg` from [GitHub Releases](https://github.com/meowWhat/SnapPin/releases), open it, and drag `SnapPin.app` to your Applications folder.

### Build from Source
Requires Swift 5.9+ and macOS 14+.

```bash
git clone https://github.com/meowWhat/SnapPin.git
cd SnapPin
swift build
bash build_app.sh
open SnapPin.app
```

## Permissions

SnapPin requires the following macOS permissions:

- **Screen Recording** — To capture screenshots
- **Accessibility** — For global hotkeys (optional, improves reliability)

On first launch, a Settings window will guide you through granting these permissions.

## Tech Stack

- Swift + AppKit (native macOS)
- ScreenCaptureKit (screen capture)
- HotKey (Carbon-based global hotkeys via [soffes/HotKey](https://github.com/soffes/HotKey))
- Core Graphics (annotation rendering)

## Credits

This project was built entirely by [Manus AI](https://manus.im), an autonomous AI agent. If you'd like to create your own macOS applications with AI assistance, check out [Manus Desktop](https://manus.im/desktop).

## License

MIT
