import Cocoa
import Carbon
import HotKey

class AppDelegate: NSObject, NSApplicationDelegate {
    
    var statusItem: NSStatusItem!
    var screenshotManager: ScreenshotManager!
    var pinManager: PinManager!
    var settingsController: SettingsWindowController!
    
    // HotKey library instances (Carbon RegisterEventHotKey under the hood)
    // F1, F2, F3 are all handled here; their behaviour depends on capture state.
    private var screenshotHotKey: HotKey?   // F1
    private var recordHotKey: HotKey?       // F2
    private var ocrHotKey: HotKey?          // F3

    // Local monitor for overlay window key events
    var localKeyMonitor: Any?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        pinManager = PinManager()
        screenshotManager = ScreenshotManager(pinManager: pinManager)
        setupStatusItem()
        NSApp.setActivationPolicy(.accessory)
        
        // Pass status button to RecordingManager for red-dot indicator
        RecordingManager.shared.statusButton = statusItem.button
        RecordingManager.shared.onRecordingFinished = { [weak self] success, path in
            if success, let path = path {
                print("[SnapPin] Recording saved: \(path)")
            }
            // Restore status bar icon
            DispatchQueue.main.async {
                self?.statusItem.button?.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "SnapPin")
                self?.statusItem.button?.contentTintColor = nil
            }
        }
        
        // Always register hotkeys immediately on launch
        registerHotkeys()
        
        // Setup settings controller with hotkey change callback
        settingsController = SettingsWindowController()
        settingsController.onHotkeyChanged = { [weak self] in
            self?.registerHotkeys()
        }
        
        // Always show settings on app launch
        settingsController.forceShow()
        
        // Install SIGTERM handler for auto-relaunch after permission changes
        installTerminationHandler()
        
        print("[SnapPin] App launched, hotkeys registered")
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        unregisterHotkeys()
    }
    
    // MARK: - Auto-Relaunch on Permission Change
    
    private func installTerminationHandler() {
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        signal(SIGTERM, SIG_IGN)
        source.setEventHandler {
            let bundleURL = Bundle.main.bundleURL
            DispatchQueue.global().async {
                Thread.sleep(forTimeInterval: 0.5)
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                task.arguments = [bundleURL.path]
                try? task.run()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.terminate(nil)
            }
        }
        source.resume()
        _signalSource = source
    }
    
    private var _signalSource: DispatchSourceSignal?
    
    // MARK: - Status Bar
    
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "SnapPin")
            button.image?.size = NSSize(width: 18, height: 18)
        }
        
        let menu = NSMenu()

        // ── Capture ──────────────────────────────────────────────────────────
        let ssItem = NSMenuItem(title: "Take Screenshot  (F1)", action: #selector(takeScreenshot), keyEquivalent: "")
        ssItem.toolTip = "F1 — Start screenshot. After drawing a selection:\n  F1 again → Pin\n  F2 → Record screen\n  F3 → Extract text (OCR)\n  Esc → Cancel"
        menu.addItem(ssItem)

        menu.addItem(NSMenuItem.separator())

        // ── Recording ────────────────────────────────────────────────────────
        let recItem = NSMenuItem(title: "Record Screen  (F2 after screenshot)", action: #selector(startRecording), keyEquivalent: "")
        recItem.toolTip = "Press F1 first, draw a selection, then press F2 to start recording. Press F2 again to stop."
        menu.addItem(recItem)

        let stopItem = NSMenuItem(title: "Stop Recording  (F2)", action: #selector(stopRecording), keyEquivalent: "")
        stopItem.toolTip = "Press F2 to stop the current recording and save."
        menu.addItem(stopItem)

        menu.addItem(NSMenuItem.separator())

        // ── Pins ─────────────────────────────────────────────────────────────
        menu.addItem(NSMenuItem(title: "Close All Pins", action: #selector(closeAllPins), keyEquivalent: ""))

        menu.addItem(NSMenuItem.separator())

        // ── App ──────────────────────────────────────────────────────────────
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit SnapPin", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    // MARK: - Global Hotkeys
    
    func registerHotkeys() {
        // Clear existing hotkeys
        screenshotHotKey = nil
        recordHotKey = nil
        ocrHotKey = nil

        // ── F1: Screenshot / Pin ──────────────────────────────────────────────
        // • No active selection → start screenshot
        // • Active selection (not text editing) → Pin
        let ssConfig = SettingsWindowController.screenshotHotkey()
        screenshotHotKey = HotKey(key: ssConfig.key, modifiers: ssConfig.modifiers)
        screenshotHotKey?.keyDownHandler = { [weak self] in
            guard let self = self else { return }
            if self.screenshotManager.hasActiveSelection && !self.screenshotManager.isInTextEditingMode {
                print("[SnapPin] F1 — Pin action")
                self.screenshotManager.handleF3()
            } else if !self.screenshotManager.hasActiveSelection {
                print("[SnapPin] F1 — Start screenshot")
                self.takeScreenshot()
            }
        }

        // ── F2: Record (only when there is an active selection) / Stop recording ──
        // • Recording in progress → stop
        // • Active selection (not recording) → start recording that region
        // • No selection, not recording → ignored
        let recConfig = SettingsWindowController.recordHotkey()
        recordHotKey = HotKey(key: recConfig.key, modifiers: recConfig.modifiers)
        recordHotKey?.keyDownHandler = { [weak self] in
            guard let self = self else { return }
            if RecordingManager.shared.state == .recording {
                print("[SnapPin] F2 — Stop recording")
                self.stopRecording()
            } else if self.screenshotManager.hasActiveSelection && !self.screenshotManager.isInTextEditingMode {
                print("[SnapPin] F2 — Start recording selected region")
                self.screenshotManager.handleRecord()
            }
            // If no selection and not recording: do nothing
        }

        // ── F3: OCR (only when there is an active selection) ─────────────────
        // • Active selection (not text editing) → OCR
        // • Otherwise → ignored
        let ocrConfig = SettingsWindowController.ocrHotkey()
        ocrHotKey = HotKey(key: ocrConfig.key, modifiers: ocrConfig.modifiers)
        ocrHotKey?.keyDownHandler = { [weak self] in
            guard let self = self else { return }
            if self.screenshotManager.hasActiveSelection && !self.screenshotManager.isInTextEditingMode {
                print("[SnapPin] F3 — OCR action")
                self.screenshotManager.handleOCR()
            }
            // If no selection: do nothing
        }

        // Local monitor for overlay window key events (Cmd+C, Enter, Esc)
        if localKeyMonitor == nil {
            localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if self?.handleLocalKeyEvent(event) == true {
                    return nil
                }
                return event
            }
        }

        print("[SnapPin] Hotkeys registered — F1: Screenshot/Pin, F2: Record/Stop, F3: OCR")
    }

    func unregisterHotkeys() {
        screenshotHotKey = nil
        recordHotKey = nil
        ocrHotKey = nil

        if let m = localKeyMonitor {
            NSEvent.removeMonitor(m)
            localKeyMonitor = nil
        }
    }
    
    /// Handle key events when our overlay window is active (local monitor)
    @discardableResult
    private func handleLocalKeyEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.function)

        // Cmd+C during capture: copy and close
        if flags.contains(.command) && event.charactersIgnoringModifiers == "c" {
            if screenshotManager.hasActiveSelection {
                print("[SnapPin] Cmd+C — copy action")
                screenshotManager.handleCmdC()
                return true
            }
        }
        
        // Enter during capture (not in text editing): copy and close
        if event.keyCode == 36 || event.keyCode == 76 {
            if screenshotManager.hasActiveSelection && !screenshotManager.isInTextEditingMode {
                print("[SnapPin] Enter — copy action")
                screenshotManager.handleCmdC()
                return true
            }
        }
        
        // Escape during capture: cancel
        if event.keyCode == 53 {
            if screenshotManager.isCapturing {
                screenshotManager.cancelCapture()
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Actions
    
    @objc func takeScreenshot() {
        screenshotManager.startCapture()
    }

    @objc func startRecording() {
        // Used by menu item only — starts the selection UI in recording mode
        screenshotManager.startCaptureForRecording()
    }

    @objc func stopRecording() {
        RecordingManager.shared.stopRecording()
    }
    
    @objc func closeAllPins() {
        pinManager.closeAllPins()
    }
    
    @objc func showSettings() {
        settingsController.forceShow()
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
