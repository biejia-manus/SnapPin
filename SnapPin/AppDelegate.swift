import Cocoa
import Carbon
import HotKey

class AppDelegate: NSObject, NSApplicationDelegate {
    
    var statusItem: NSStatusItem!
    var screenshotManager: ScreenshotManager!
    var pinManager: PinManager!
    var settingsController: SettingsWindowController!
    
    // HotKey library instances (Carbon RegisterEventHotKey under the hood)
    private var screenshotHotKey: HotKey?
    private var pinHotKey: HotKey?
    private var recordHotKey: HotKey?

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
        menu.addItem(NSMenuItem(title: "Screenshot (F1)", action: #selector(takeScreenshot), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Record Screen (F2)", action: #selector(startRecording), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Stop Recording", action: #selector(stopRecording), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Close All Pins", action: #selector(closeAllPins), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit SnapPin", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    // MARK: - Global Hotkeys
    
    func registerHotkeys() {
        // Clear existing hotkeys
        screenshotHotKey = nil
        pinHotKey = nil
        recordHotKey = nil

        let ssConfig = SettingsWindowController.screenshotHotkey()
        screenshotHotKey = HotKey(key: ssConfig.key, modifiers: ssConfig.modifiers)
        screenshotHotKey?.keyDownHandler = { [weak self] in
            print("[SnapPin] Screenshot hotkey pressed")
            self?.takeScreenshot()
        }

        let pinConfig = SettingsWindowController.pinHotkey()
        pinHotKey = HotKey(key: pinConfig.key, modifiers: pinConfig.modifiers)
        pinHotKey?.keyDownHandler = { [weak self] in
            print("[SnapPin] Pin hotkey pressed")
            self?.screenshotManager.handleF3()
        }

        // Record hotkey (F2 by default) — toggle start/stop
        let recConfig = SettingsWindowController.recordHotkey()
        recordHotKey = HotKey(key: recConfig.key, modifiers: recConfig.modifiers)
        recordHotKey?.keyDownHandler = { [weak self] in
            print("[SnapPin] Record hotkey pressed")
            if RecordingManager.shared.state == .recording {
                self?.stopRecording()
            } else {
                self?.startRecording()
            }
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

        print("[SnapPin] Hotkeys registered: Screenshot=\(ssConfig.key), Pin=\(pinConfig.key), Record=\(recConfig.key)")
    }

    func unregisterHotkeys() {
        screenshotHotKey = nil
        pinHotKey = nil
        recordHotKey = nil

        if let m = localKeyMonitor {
            NSEvent.removeMonitor(m)
            localKeyMonitor = nil
        }
    }
    
    /// Handle key events when our overlay window is active
    @discardableResult
    private func handleLocalKeyEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.function)
        
        // Cmd+C during capture: copy and close
        if flags.contains(.command) && event.charactersIgnoringModifiers == "c" {
            if screenshotManager.hasActiveSelection {
                print("[SnapPin] Cmd+C pressed during capture - copy action")
                screenshotManager.handleCmdC()
                return true
            }
        }
        
        // Enter during capture (not in text editing): copy and close
        if event.keyCode == 36 || event.keyCode == 76 {
            if screenshotManager.hasActiveSelection && !screenshotManager.isInTextEditingMode {
                print("[SnapPin] Enter pressed during capture - copy action")
                screenshotManager.handleCmdC()
                return true
            }
        }
        
        // Escape during capture: cancel
        if event.keyCode == 53 {
            if screenshotManager.hasActiveSelection {
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
        // Use the same selection UI as screenshot, but in recording mode
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
