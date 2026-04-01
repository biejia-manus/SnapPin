# Changelog

All notable changes to SnapPin are documented in this file.

---

## [v1.4.0] — 2026-04-01

### Added
- **OCR (Extract Text)**: Press **F3** after drawing a selection to recognize text in the captured region using Apple Vision Framework. Works fully offline — no internet or API key required. Supports Simplified Chinese, Traditional Chinese, and English. Recognized text is automatically copied to the clipboard.
- **OCR result HUD**: A floating card appears briefly after OCR, showing a preview of the recognized text (up to 6 lines) and confirming it has been copied. Redesigned with a light background and dark text for clear readability in any system appearance.
- **In-overlay tooltips**: Hovering over any button in the screenshot toolbar now shows a tooltip with the button's name and keyboard shortcut, rendered directly inside the overlay (bypassing the macOS system tooltip limitation at shielding window level).

### Changed
- **Unified F1 shortcut**: F1 now serves dual purpose — press once to start screenshot, press again (with an active selection) to Pin. The separate F3 Pin shortcut has been removed.
- **F3 reassigned to OCR**: F3 now triggers OCR on the current selection (previously it was the Pin shortcut).
- **F2 for recording**: F2 starts screen recording when a selection is active; press F2 again to stop and open the save dialog.
- **Toolbar tooltips**: Removed the shortcut key labels below toolbar icons; replaced with hover tooltips for a cleaner toolbar appearance.
- **Status bar menu**: Reorganized into logical groups (Capture / Recording / Pins / App) with descriptive tooltips on each item.
- **Settings**: Removed the separate Pin shortcut row; updated hint text to reflect the new F1/F2/F3 flow.

---

## [v1.0.3] — 2025-03-26

### Added
- **Screen recording**: Press F2 to select a region and start recording. Supports export to MP4 (H.264) and GIF formats.
- **Recording indicator**: A red border is displayed around the recording region while recording is in progress. The border is excluded from the captured content and does not appear in saved files.
- **Recording hotkey setting**: The record hotkey (default F2) is now configurable in Settings.
- **Hotkey order**: Settings panel now lists hotkeys in F1 / F2 / F3 order (Screenshot / Record / Pin).

### Fixed
- Trackpad two-finger scroll and pinch-to-zoom now both trigger zoom on pinned screenshots, consistent with mouse scroll wheel behavior.

### Changed
- `build_app.sh` now includes the full compile + bundle + sign workflow (previously split across `build_app.sh` and `build_local.sh`). All paths are resolved dynamically using `$(dirname "$0")` — no hardcoded user paths.
- `create_dmg.sh` paths are also fully dynamic.
- Removed `build_local.sh` (superseded by the updated `build_app.sh`).

---

## [v1.2.0] — 2025-03-24

### Added
- Auto-open Settings window on every app launch for easier first-time setup.
- Settings window automatically reopens after granting permissions and relaunching.

### Fixed
- Removed ad-hoc signing from the DMG itself to avoid a double Gatekeeper prompt on first open.
- Reverted menu bar icon to scissors (consistent with app identity).

### Changed
- Optimized `AppIcon.icns` file size from 1.9 MB to 903 KB.

---

## [v1.1.0] — 2025-03-22

### Added
- Save button in the screenshot toolbar to save directly to disk.
- App icon added to the bundle.

### Fixed
- Improved permission request UX: clearer prompts and guidance when Screen Recording or Accessibility permissions are not granted.

---

## [v1.0.0] — 2025-03-20

### Initial Release

- **F1** — Freeze screen and drag to select a screenshot region.
- **F3** — Pin the last screenshot onto the screen as a floating window.
- Annotation tools: arrow, rectangle, text, mosaic, color picker.
- Pinned screenshots support scroll-to-zoom and drag-to-move.
- Customizable hotkeys (F1–F12 or modifier + key combinations).
- Menu bar icon with quick access to Settings and permissions.
- Built entirely with Swift + AppKit + ScreenCaptureKit. No Electron, no dependencies beyond HotKey.
