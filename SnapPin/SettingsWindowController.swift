import Cocoa
import Carbon
import HotKey
import ScreenCaptureKit

class SettingsWindowController: NSObject {
    
    // Bump this version whenever the app is updated and needs re-onboarding
    static let currentOnboardingVersion = 8
    
    private var window: NSWindow?
    
    // Callback to re-register hotkeys when user changes them
    var onHotkeyChanged: (() -> Void)?
    
    // MARK: - UserDefaults keys for custom hotkeys
    static let screenshotKeyCodeKey = "screenshotKeyCode"
    static let screenshotModifiersKey = "screenshotModifiers"
    static let pinKeyCodeKey = "pinKeyCode"
    static let pinModifiersKey = "pinModifiers"
    static let recordKeyCodeKey = "recordKeyCode"
    static let recordModifiersKey = "recordModifiers"
    static let ocrKeyCodeKey = "ocrKeyCode"
    static let ocrModifiersKey = "ocrModifiers"
    // MARK: - Default hotkeys
    static let defaultScreenshotKey: Key = .f1
    static let defaultScreenshotModifiers: NSEvent.ModifierFlags = []
    static let defaultPinKey: Key = .f3
    static let defaultPinModifiers: NSEvent.ModifierFlags = []
    static let defaultRecordKey: Key = .f2
    static let defaultRecordModifiers: NSEvent.ModifierFlags = []
    static let defaultOCRKey: Key = .f3
    static let defaultOCRModifiers: NSEvent.ModifierFlags = []
    
    // MARK: - Get current hotkey settings
    
    static func screenshotHotkey() -> (key: Key, modifiers: NSEvent.ModifierFlags) {
        let defaults = UserDefaults.standard
        if let rawKey = defaults.object(forKey: screenshotKeyCodeKey) as? UInt32 {
            let rawMods = defaults.integer(forKey: screenshotModifiersKey)
            if let key = Key(carbonKeyCode: rawKey) {
                return (key, NSEvent.ModifierFlags(rawValue: UInt(rawMods)))
            }
        }
        return (defaultScreenshotKey, defaultScreenshotModifiers)
    }
    
    static func pinHotkey() -> (key: Key, modifiers: NSEvent.ModifierFlags) {
        let defaults = UserDefaults.standard
        if let rawKey = defaults.object(forKey: pinKeyCodeKey) as? UInt32 {
            let rawMods = defaults.integer(forKey: pinModifiersKey)
            if let key = Key(carbonKeyCode: rawKey) {
                return (key, NSEvent.ModifierFlags(rawValue: UInt(rawMods)))
            }
        }
        return (defaultPinKey, defaultPinModifiers)
    }

    static func recordHotkey() -> (key: Key, modifiers: NSEvent.ModifierFlags) {
        let defaults = UserDefaults.standard
        if let rawKey = defaults.object(forKey: recordKeyCodeKey) as? UInt32 {
            let rawMods = defaults.integer(forKey: recordModifiersKey)
            if let key = Key(carbonKeyCode: rawKey) {
                return (key, NSEvent.ModifierFlags(rawValue: UInt(rawMods)))
            }
        }
        return (defaultRecordKey, defaultRecordModifiers)
    }

    static func ocrHotkey() -> (key: Key, modifiers: NSEvent.ModifierFlags) {
        let defaults = UserDefaults.standard
        if let rawKey = defaults.object(forKey: ocrKeyCodeKey) as? UInt32 {
            let rawMods = defaults.integer(forKey: ocrModifiersKey)
            if let key = Key(carbonKeyCode: rawKey) {
                return (key, NSEvent.ModifierFlags(rawValue: UInt(rawMods)))
            }
        }
        return (defaultOCRKey, defaultOCRModifiers)
    }
    
    // MARK: - Hotkey recording state
    private var isRecordingScreenshot = false
    private var isRecordingPin = false
    private var isRecordingRecord = false
    private var isRecordingOCR = false
    private var screenshotHotkeyButton: NSButton?
    private var pinHotkeyButton: NSButton?
    private var recordHotkeyButton: NSButton?
    private var ocrHotkeyButton: NSButton?
    private var keyMonitor: Any?
    
    // Permission status indicators
    private var screenRecordingStatus: NSTextField?
    private var accessibilityStatus: NSTextField?

    // Timer for polling permission status
    private var permissionTimer: Timer?
    
    // MARK: - Show/Hide
    
    func showIfNeeded() {
        let savedVersion = UserDefaults.standard.integer(forKey: "onboardingVersion")
        if savedVersion >= SettingsWindowController.currentOnboardingVersion {
            return
        }
        showSettingsWindow()
    }
    
    func forceShow() {
        showSettingsWindow()
    }
    
    private func showSettingsWindow() {
        // If window already exists, just bring it to front
        if let w = window, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            refreshPermissionStatus()
            startPermissionPolling()
            return
        }
        
        let w: CGFloat = 480
        let h: CGFloat = 460
        
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let rect = NSRect(x: (screenFrame.width - w) / 2, y: (screenFrame.height - h) / 2, width: w, height: h)
        
        // Use .normal level so system permission dialogs can appear on top
        window = NSWindow(contentRect: rect, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window?.title = "SnapPin Settings"
        window?.isReleasedWhenClosed = false
        window?.level = .normal
        window?.delegate = self
        
        let cv = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        cv.wantsLayer = true
        
        var y = h - 50
        
        // Title
        let title = makeLabel("SnapPin", font: .systemFont(ofSize: 26, weight: .bold), frame: NSRect(x: 0, y: y, width: w, height: 32))
        title.alignment = .center
        cv.addSubview(title)
        y -= 24
        
        let subtitle = makeLabel("Screenshot · Pin · Record · OCR for macOS", font: .systemFont(ofSize: 13), frame: NSRect(x: 0, y: y, width: w, height: 18))
        subtitle.alignment = .center
        subtitle.textColor = .secondaryLabelColor
        cv.addSubview(subtitle)
        y -= 24
        
        // === Hotkeys Section ===
        let sep1 = NSBox(frame: NSRect(x: 30, y: y, width: w - 60, height: 1))
        sep1.boxType = .separator
        cv.addSubview(sep1)
        y -= 28
        
        let hkTitle = makeLabel("Hotkeys", font: .systemFont(ofSize: 15, weight: .semibold), frame: NSRect(x: 30, y: y, width: w - 60, height: 20))
        cv.addSubview(hkTitle)
        y -= 32
        
        // Screenshot hotkey row (F1)
        let ssLabel = makeLabel("Screenshot:", font: .systemFont(ofSize: 13), frame: NSRect(x: 40, y: y + 2, width: 100, height: 24))
        cv.addSubview(ssLabel)
        
        let ssHotkey = SettingsWindowController.screenshotHotkey()
        let ssBtn = NSButton(frame: NSRect(x: 150, y: y, width: 180, height: 26))
        ssBtn.title = hotkeyDisplayString(key: ssHotkey.key, modifiers: ssHotkey.modifiers)
        ssBtn.bezelStyle = .rounded
        ssBtn.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        ssBtn.target = self
        ssBtn.action = #selector(startRecordingScreenshotHotkey)
        cv.addSubview(ssBtn)
        screenshotHotkeyButton = ssBtn
        
        let ssReset = NSButton(frame: NSRect(x: 340, y: y, width: 70, height: 26))
        ssReset.title = "Reset"
        ssReset.bezelStyle = .rounded
        ssReset.controlSize = .small
        ssReset.font = .systemFont(ofSize: 11)
        ssReset.target = self
        ssReset.action = #selector(resetScreenshotHotkey)
        cv.addSubview(ssReset)
        y -= 32

        // Record hotkey row (F2)
        let recLabel = makeLabel("Record:", font: .systemFont(ofSize: 13), frame: NSRect(x: 40, y: y + 2, width: 100, height: 24))
        cv.addSubview(recLabel)

        let recHotkey = SettingsWindowController.recordHotkey()
        let recBtn = NSButton(frame: NSRect(x: 150, y: y, width: 180, height: 26))
        recBtn.title = hotkeyDisplayString(key: recHotkey.key, modifiers: recHotkey.modifiers)
        recBtn.bezelStyle = .rounded
        recBtn.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        recBtn.target = self
        recBtn.action = #selector(startRecordingRecordHotkey)
        cv.addSubview(recBtn)
        recordHotkeyButton = recBtn

        let recReset = NSButton(frame: NSRect(x: 340, y: y, width: 70, height: 26))
        recReset.title = "Reset"
        recReset.bezelStyle = .rounded
        recReset.controlSize = .small
        recReset.font = .systemFont(ofSize: 11)
        recReset.target = self
        recReset.action = #selector(resetRecordHotkey)
        cv.addSubview(recReset)
        y -= 32

        // OCR hotkey row (F3)
        let ocrLabel = makeLabel("OCR:", font: .systemFont(ofSize: 13), frame: NSRect(x: 40, y: y + 2, width: 100, height: 24))
        cv.addSubview(ocrLabel)

        let ocrHotkey = SettingsWindowController.ocrHotkey()
        let ocrBtn = NSButton(frame: NSRect(x: 150, y: y, width: 180, height: 26))
        ocrBtn.title = hotkeyDisplayString(key: ocrHotkey.key, modifiers: ocrHotkey.modifiers)
        ocrBtn.bezelStyle = .rounded
        ocrBtn.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        ocrBtn.target = self
        ocrBtn.action = #selector(startRecordingOCRHotkey)
        cv.addSubview(ocrBtn)
        ocrHotkeyButton = ocrBtn

        let ocrReset = NSButton(frame: NSRect(x: 340, y: y, width: 70, height: 26))
        ocrReset.title = "Reset"
        ocrReset.bezelStyle = .rounded
        ocrReset.controlSize = .small
        ocrReset.font = .systemFont(ofSize: 11)
        ocrReset.target = self
        ocrReset.action = #selector(resetOCRHotkey)
        cv.addSubview(ocrReset)
        y -= 20

        let hkHint = makeLabel("F1: Screenshot → F1 Pin  |  F2 Record  |  F3 OCR  |  ⌘C Copy  |  Esc Cancel", font: .systemFont(ofSize: 11), frame: NSRect(x: 40, y: y, width: w - 80, height: 14))
        hkHint.textColor = .tertiaryLabelColor
        cv.addSubview(hkHint)
        y -= 32

        // === Permissions Section ===
        let sep2 = NSBox(frame: NSRect(x: 30, y: y, width: w - 60, height: 1))
        sep2.boxType = .separator
        cv.addSubview(sep2)
        y -= 28
        
        let permTitle = makeLabel("Permissions", font: .systemFont(ofSize: 15, weight: .semibold), frame: NSRect(x: 30, y: y, width: w - 60, height: 20))
        cv.addSubview(permTitle)
        y -= 34
        
        // Screen Recording permission row
        let srIcon = NSImageView(frame: NSRect(x: 40, y: y, width: 20, height: 20))
        if let img = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: "Screen Recording") {
            srIcon.image = img
            srIcon.contentTintColor = .systemBlue
        }
        cv.addSubview(srIcon)
        
        let srLabel = makeLabel("Screen Recording", font: .systemFont(ofSize: 13, weight: .medium), frame: NSRect(x: 68, y: y, width: 160, height: 20))
        cv.addSubview(srLabel)
        
        let srStatusLabel = makeLabel("Checking...", font: .systemFont(ofSize: 12), frame: NSRect(x: 230, y: y, width: 100, height: 20))
        srStatusLabel.alignment = .right
        cv.addSubview(srStatusLabel)
        screenRecordingStatus = srStatusLabel
        
        let srBtn = NSButton(frame: NSRect(x: 340, y: y - 2, width: 100, height: 24))
        srBtn.title = "Request"
        srBtn.bezelStyle = .rounded
        srBtn.controlSize = .small
        srBtn.font = .systemFont(ofSize: 11)
        srBtn.target = self
        srBtn.action = #selector(requestScreenRecording)
        cv.addSubview(srBtn)
        y -= 32
        
        // Accessibility permission row
        let accIcon = NSImageView(frame: NSRect(x: 40, y: y, width: 20, height: 20))
        if let img = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Accessibility") {
            accIcon.image = img
            accIcon.contentTintColor = .systemBlue
        }
        cv.addSubview(accIcon)
        
        let accLabel = makeLabel("Accessibility", font: .systemFont(ofSize: 13, weight: .medium), frame: NSRect(x: 68, y: y, width: 160, height: 20))
        cv.addSubview(accLabel)
        
        let accStatusLabel = makeLabel("Checking...", font: .systemFont(ofSize: 12), frame: NSRect(x: 230, y: y, width: 100, height: 20))
        accStatusLabel.alignment = .right
        cv.addSubview(accStatusLabel)
        accessibilityStatus = accStatusLabel
        
        let accBtn = NSButton(frame: NSRect(x: 340, y: y - 2, width: 100, height: 24))
        accBtn.title = "Request"
        accBtn.bezelStyle = .rounded
        accBtn.controlSize = .small
        accBtn.font = .systemFont(ofSize: 11)
        accBtn.target = self
        accBtn.action = #selector(requestAccessibility)
        cv.addSubview(accBtn)
        y -= 20
        
        let permHint = makeLabel("Click \"Request\" to trigger the system permission dialog.", font: .systemFont(ofSize: 11), frame: NSRect(x: 40, y: y, width: w - 80, height: 14))
        permHint.textColor = .tertiaryLabelColor
        cv.addSubview(permHint)
        
        // Version label
        let verLabel = makeLabel(
            "v1.0.0",
            font: .systemFont(ofSize: 10),
            frame: NSRect(x: 30, y: 16, width: 60, height: 14)
        )
        verLabel.textColor = .tertiaryLabelColor
        cv.addSubview(verLabel)
        
        // Done button
        let doneBtn = NSButton(frame: NSRect(x: w - 130, y: 12, width: 100, height: 32))
        doneBtn.title = "Done"
        doneBtn.bezelStyle = .rounded
        doneBtn.keyEquivalent = "\r"
        doneBtn.contentTintColor = .white
        doneBtn.target = self
        doneBtn.action = #selector(doneAction)
        cv.addSubview(doneBtn)
        
        window?.contentView = cv
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Check permission status and start polling
        refreshPermissionStatus()
        startPermissionPolling()
    }
    
    // MARK: - Permission Polling
    
    private func startPermissionPolling() {
        stopPermissionPolling()
        // Poll every 2 seconds to detect permission changes in real time
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshPermissionStatus()
        }
    }
    
    private func stopPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }
    
    // MARK: - Permission Status
    
    private func refreshPermissionStatus() {
        // Screen Recording: check via CGPreflightScreenCaptureAccess (macOS 15+)
        let hasScreenRecording = CGPreflightScreenCaptureAccess()
        screenRecordingStatus?.stringValue = hasScreenRecording ? "Granted" : "Not Granted"
        screenRecordingStatus?.textColor = hasScreenRecording ? .systemGreen : .systemOrange
        
        // Accessibility
        let hasAccessibility = AXIsProcessTrusted()
        accessibilityStatus?.stringValue = hasAccessibility ? "Granted" : "Not Granted"
        accessibilityStatus?.textColor = hasAccessibility ? .systemGreen : .systemOrange
    }
    
    // MARK: - Permission Requests
    
    @objc private func requestScreenRecording() {
        // Temporarily send our window behind so system dialog appears on top
        window?.orderBack(nil)
        
        // CGRequestScreenCaptureAccess triggers the system permission dialog
        let granted = CGRequestScreenCaptureAccess()
        if !granted {
            // Also try ScreenCaptureKit which triggers the dialog on macOS 14+
            if #available(macOS 14.0, *) {
                Task {
                    do {
                        _ = try await SCShareableContent.current
                    } catch {
                        print("[SnapPin] SCShareableContent request error: \(error)")
                    }
                    await MainActor.run {
                        self.refreshPermissionStatus()
                    }
                }
            }
        }
        // Refresh after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshPermissionStatus()
        }
    }
    
    @objc private func requestAccessibility() {
        // Temporarily send our window behind so system dialog appears on top
        window?.orderBack(nil)
        
        // This triggers the system accessibility permission dialog
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        // Refresh after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshPermissionStatus()
        }
    }
    
    // MARK: - Hotkey Display String
    
    private func hotkeyDisplayString(key: Key, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("\u{2303}") }
        if modifiers.contains(.option) { parts.append("\u{2325}") }
        if modifiers.contains(.shift) { parts.append("\u{21E7}") }
        if modifiers.contains(.command) { parts.append("\u{2318}") }
        parts.append(keyDisplayName(key))
        return parts.joined(separator: " ")
    }
    
    private func keyDisplayName(_ key: Key) -> String {
        switch key {
        case .f1: return "F1"
        case .f2: return "F2"
        case .f3: return "F3"
        case .f4: return "F4"
        case .f5: return "F5"
        case .f6: return "F6"
        case .f7: return "F7"
        case .f8: return "F8"
        case .f9: return "F9"
        case .f10: return "F10"
        case .f11: return "F11"
        case .f12: return "F12"
        case .a: return "A"
        case .b: return "B"
        case .c: return "C"
        case .d: return "D"
        case .e: return "E"
        case .f: return "F"
        case .g: return "G"
        case .h: return "H"
        case .i: return "I"
        case .j: return "J"
        case .k: return "K"
        case .l: return "L"
        case .m: return "M"
        case .n: return "N"
        case .o: return "O"
        case .p: return "P"
        case .q: return "Q"
        case .r: return "R"
        case .s: return "S"
        case .t: return "T"
        case .u: return "U"
        case .v: return "V"
        case .w: return "W"
        case .x: return "X"
        case .y: return "Y"
        case .z: return "Z"
        case .space: return "Space"
        case .escape: return "Esc"
        case .delete: return "Delete"
        case .tab: return "Tab"
        case .return: return "Return"
        default: return "\(key)"
        }
    }
    
    // MARK: - Hotkey Recording
    
    @objc private func startRecordingScreenshotHotkey() {
        stopRecording()
        isRecordingScreenshot = true
        screenshotHotkeyButton?.title = "Press a key..."
        startKeyMonitor()
    }
    
    @objc private func startRecordingPinHotkey() {
        stopRecording()
        isRecordingPin = true
        pinHotkeyButton?.title = "Press a key..."
        startKeyMonitor()
    }

    @objc private func startRecordingRecordHotkey() {
        stopRecording()
        isRecordingRecord = true
        recordHotkeyButton?.title = "Press a key..."
        startKeyMonitor()
    }

    @objc private func startRecordingOCRHotkey() {
        stopRecording()
        isRecordingOCR = true
        ocrHotkeyButton?.title = "Press a key..."
        startKeyMonitor()
    }
    
    private func startKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleRecordedKey(event)
            return nil // consume the event
        }
    }
    
    private func stopRecording() {
        isRecordingScreenshot = false
        isRecordingPin = false
        isRecordingRecord = false
        isRecordingOCR = false
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }
    
    private func handleRecordedKey(_ event: NSEvent) {
        // Strip .function and .numericPad from modifiers so fn key is not required
        // Keep only the meaningful modifier flags: control, option, shift, command
        let flags = event.modifierFlags
            .intersection([.control, .option, .shift, .command])
        
        // Convert NSEvent keyCode to Carbon keyCode for HotKey library
        let carbonKeyCode = UInt32(event.keyCode)
        guard let key = Key(carbonKeyCode: carbonKeyCode) else {
            stopRecording()
            return
        }
        
        // Reject bare modifier-only presses (no actual key)
        // keyCode 54/55 = Cmd, 56/60 = Shift, 58/61 = Option, 59/62 = Ctrl
        let modifierKeyCodes: Set<UInt32> = [54, 55, 56, 60, 58, 61, 59, 62, 63]
        if modifierKeyCodes.contains(carbonKeyCode) {
            // User only pressed a modifier key — keep waiting
            return
        }
        
        // For non-function keys (letters, numbers, etc.) without any modifier,
        // require at least one modifier to avoid conflicts with normal typing.
        // Exception: F1–F12 keys are safe to use alone.
        let isFunctionKey: Bool = {
            let fnKeys: Set<Key> = [.f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12]
            return fnKeys.contains(key)
        }()
        
        if flags.isEmpty && !isFunctionKey {
            // Show a warning hint in the button and keep recording
            if isRecordingScreenshot {
                screenshotHotkeyButton?.title = "Add ⌃/⌥/⇧/⌘ ..."
            } else if isRecordingPin {
                pinHotkeyButton?.title = "Add ⌃/⌥/⇧/⌘ ..."
            } else if isRecordingRecord {
                recordHotkeyButton?.title = "Add ⌃/⌥/⇧/⌘ ..."
            } else if isRecordingOCR {
                ocrHotkeyButton?.title = "Add ⌃/⌥/⇧/⌘ ..."
            }
            return
        }
        
        let displayStr = hotkeyDisplayString(key: key, modifiers: flags)
        
        if isRecordingScreenshot {
            UserDefaults.standard.set(carbonKeyCode, forKey: SettingsWindowController.screenshotKeyCodeKey)
            UserDefaults.standard.set(Int(flags.rawValue), forKey: SettingsWindowController.screenshotModifiersKey)
            screenshotHotkeyButton?.title = displayStr
        } else if isRecordingPin {
            UserDefaults.standard.set(carbonKeyCode, forKey: SettingsWindowController.pinKeyCodeKey)
            UserDefaults.standard.set(Int(flags.rawValue), forKey: SettingsWindowController.pinModifiersKey)
            pinHotkeyButton?.title = displayStr
        } else if isRecordingRecord {
            UserDefaults.standard.set(carbonKeyCode, forKey: SettingsWindowController.recordKeyCodeKey)
            UserDefaults.standard.set(Int(flags.rawValue), forKey: SettingsWindowController.recordModifiersKey)
            recordHotkeyButton?.title = displayStr
        } else if isRecordingOCR {
            UserDefaults.standard.set(carbonKeyCode, forKey: SettingsWindowController.ocrKeyCodeKey)
            UserDefaults.standard.set(Int(flags.rawValue), forKey: SettingsWindowController.ocrModifiersKey)
            ocrHotkeyButton?.title = displayStr
        }
        
        stopRecording()
        onHotkeyChanged?()
    }
    
    @objc private func resetScreenshotHotkey() {
        UserDefaults.standard.removeObject(forKey: SettingsWindowController.screenshotKeyCodeKey)
        UserDefaults.standard.removeObject(forKey: SettingsWindowController.screenshotModifiersKey)
        screenshotHotkeyButton?.title = hotkeyDisplayString(key: SettingsWindowController.defaultScreenshotKey, modifiers: SettingsWindowController.defaultScreenshotModifiers)
        onHotkeyChanged?()
    }
    
    @objc private func resetPinHotkey() {
        UserDefaults.standard.removeObject(forKey: SettingsWindowController.pinKeyCodeKey)
        UserDefaults.standard.removeObject(forKey: SettingsWindowController.pinModifiersKey)
        pinHotkeyButton?.title = hotkeyDisplayString(key: SettingsWindowController.defaultPinKey, modifiers: SettingsWindowController.defaultPinModifiers)
        onHotkeyChanged?()
    }

    @objc private func resetRecordHotkey() {
        UserDefaults.standard.removeObject(forKey: SettingsWindowController.recordKeyCodeKey)
        UserDefaults.standard.removeObject(forKey: SettingsWindowController.recordModifiersKey)
        recordHotkeyButton?.title = hotkeyDisplayString(key: SettingsWindowController.defaultRecordKey, modifiers: SettingsWindowController.defaultRecordModifiers)
        onHotkeyChanged?()
    }

    @objc private func resetOCRHotkey() {
        UserDefaults.standard.removeObject(forKey: SettingsWindowController.ocrKeyCodeKey)
        UserDefaults.standard.removeObject(forKey: SettingsWindowController.ocrModifiersKey)
        ocrHotkeyButton?.title = hotkeyDisplayString(key: SettingsWindowController.defaultOCRKey, modifiers: SettingsWindowController.defaultOCRModifiers)
        onHotkeyChanged?()
    }
    
    // MARK: - UI Helpers
    
    private func makeLabel(_ text: String, font: NSFont, frame: NSRect) -> NSTextField {
        let l = NSTextField(frame: frame)
        l.stringValue = text
        l.font = font
        l.isBezeled = false
        l.drawsBackground = false
        l.isEditable = false
        l.isSelectable = false
        return l
    }
    
    // MARK: - Actions
    
    @objc private func doneAction() {
        UserDefaults.standard.set(SettingsWindowController.currentOnboardingVersion, forKey: "onboardingVersion")
        stopRecording()
        stopPermissionPolling()
        window?.close()
    }
    
    // MARK: - Relaunch support
    
    static func relaunchApp() {
        let url = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", url.path]
        try? task.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        }
    }
}

// MARK: - NSWindowDelegate

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        stopRecording()
        stopPermissionPolling()
    }
}
