import Cocoa
import AVFoundation
import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - RecordingManager

class RecordingManager: NSObject {

    static let shared = RecordingManager()

    private var lifecycle = RecordingLifecycle() {
        didSet {
            guard state != oldValue.state else { return }
            let newState = state
            DispatchQueue.main.async { [weak self] in
                self?.onStateChanged?(newState)
            }
        }
    }
    var state: RecordingState { lifecycle.state }

    // Callback invoked on main thread when recording stops (success or failure)
    var onRecordingFinished: ((Bool, String?) -> Void)?

    // Callback invoked on main thread whenever recording state changes
    var onStateChanged: ((RecordingState) -> Void)?

    // Status bar button reference for red-dot indicator (set by AppDelegate)
    var statusButton: NSStatusBarButton?

    // SCStream components
    private var stream: SCStream?
    private var streamOutput: RecordingStreamOutput?
    private let frameQueue = DispatchQueue(label: "snappin.recording")
    private let imageContext = CIContext()
    private var frameSessionID: UUID? // Accessed only on frameQueue.

    // Recording region (in screen coordinates, points)
    private var recordingRect: CGRect = .zero
    private var recordingScreenFrame: CGRect = .zero

    // Red border overlay window shown during recording
    private var borderWindow: NSWindow?

    // GIF frame accumulation
    private var gifFrames: [(CGImage, TimeInterval)] = []
    private var lastFrameTime: TimeInterval = 0
    private let gifFPS: Double = 10   // capture at 10fps for GIF

    // Timing
    private var startTime: CMTime = .zero
    private var firstSampleReceived = false

    // MARK: - Start recording

    func startRecording(rect: CGRect, on screen: NSScreen) {
        guard let sessionID = lifecycle.begin() else { return }
        let region = rect.intersection(screen.frame)
        guard !region.isNull, region.width >= 1, region.height >= 1 else {
            finishRecording(sessionID, success: false, message: "The recording region is outside the display.")
            return
        }
        recordingRect = region
        recordingScreenFrame = screen.frame
        updateStatusIndicator()
        showBorderWindow(rect: region, on: screen)
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0
        let borderID = borderWindow.map { CGWindowID($0.windowNumber) }
        frameQueue.async {
            self.frameSessionID = sessionID
            self.firstSampleReceived = false
            self.gifFrames.removeAll()
            self.lastFrameTime = 0
        }

        // The token check also covers F2 being pressed again during this delay.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self, self.lifecycle.sessionID == sessionID, self.state == .starting else { return }
            self.startStream(displayID: displayID, borderID: borderID, sessionID: sessionID)
        }
    }

    private func startStream(displayID: UInt32, borderID: CGWindowID?, sessionID: UUID) {
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { [weak self] content, error in
            DispatchQueue.main.async {
                guard let self = self, self.lifecycle.sessionID == sessionID, self.state == .starting else { return }
                guard let content = content else {
                    self.finishRecording(sessionID, success: false,
                        message: "Failed to get screen content: " + (error?.localizedDescription ?? "unknown"))
                    return
                }
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                    self.finishRecording(sessionID, success: false, message: "Could not find display for recording")
                    return
                }
                let excludedWindows = content.windows.filter { $0.windowID == borderID }
                let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
                let config = SCStreamConfiguration()
                config.width = display.width * 2
                config.height = display.height * 2
                config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                config.showsCursor = true
                config.captureResolution = .best
                config.pixelFormat = kCVPixelFormatType_32BGRA

                let output = RecordingStreamOutput(sessionID: sessionID)
                output.manager = self
                let stream = SCStream(filter: filter, configuration: config, delegate: output)
                self.streamOutput = output
                self.stream = stream
                do {
                    try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: self.frameQueue)
                    stream.startCapture { [weak self] error in
                        DispatchQueue.main.async {
                            guard let self = self, self.lifecycle.sessionID == sessionID else { return }
                            if let error = error {
                                self.finishRecording(sessionID, success: false,
                                    message: "Failed to start recording: \(error.localizedDescription)")
                            } else if self.state == .stopping {
                                // F2 arrived while startCapture was still in flight.
                                self.stopStream(stream, sessionID: sessionID)
                            } else if self.lifecycle.didStart(sessionID) {
                                print("[SnapPin] Recording started for rect: \(self.recordingRect)")
                            }
                        }
                    }
                } catch {
                    self.finishRecording(sessionID, success: false,
                        message: "Failed to configure recording: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Stop recording

    func stopRecording() {
        let previousState = state
        guard let sessionID = lifecycle.requestStop() else { return }
        hideBorderWindow()
        updateStatusIndicator()
        guard let stream = stream else {
            finishRecording(sessionID, success: false, message: nil)
            return
        }
        if previousState == .recording { stopStream(stream, sessionID: sessionID) }
        // During startup, its completion handler will stop the stream once ready.
    }

    private func stopStream(_ stream: SCStream, sessionID: UUID) {
        stream.stopCapture { [weak self] error in
            guard let self = self else { return }
            // Drain queued frames before accessing them on the main thread.
            self.frameQueue.async {
                if self.frameSessionID == sessionID { self.frameSessionID = nil }
                DispatchQueue.main.async {
                    guard self.lifecycle.sessionID == sessionID else { return }
                    self.stream = nil
                    self.streamOutput = nil
                    if let error = error {
                        self.finishRecording(sessionID, success: false,
                            message: "Failed to stop recording: \(error.localizedDescription)")
                    } else if self.gifFrames.isEmpty {
                        self.finishRecording(sessionID, success: false, message: "No frames captured. Please try recording again.")
                    } else {
                        self.promptSavePanel()
                    }
                }
            }
        }
    }

    func streamFailed(sessionID: UUID, error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.finishRecording(sessionID, success: false, message: "Recording interrupted: \(error.localizedDescription)")
        }
    }

    private func finishRecording(_ sessionID: UUID, success: Bool, message: String?) {
        guard lifecycle.sessionID == sessionID else { return }
        stream = nil
        streamOutput = nil
        hideBorderWindow()
        // Keep the session busy until all its frame callbacks have drained.
        frameQueue.async {
            if self.frameSessionID == sessionID { self.frameSessionID = nil }
            self.gifFrames.removeAll()
            DispatchQueue.main.async {
                guard self.lifecycle.finish(sessionID) else { return }
                self.updateStatusIndicator()
                self.onRecordingFinished?(success, message)
            }
        }
    }

    private func finishExport(success: Bool, message: String?) {
        guard let sessionID = lifecycle.sessionID else { return }
        finishRecording(sessionID, success: success, message: message)
    }

    // MARK: - Red border window

    private func showBorderWindow(rect: CGRect, on screen: NSScreen) {
        // Must run on main thread; dispatch if needed
        if Thread.isMainThread {
            _showBorderWindowOnMain(rect: rect, on: screen)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?._showBorderWindowOnMain(rect: rect, on: screen)
            }
        }
    }

    private func _showBorderWindowOnMain(rect: CGRect, on screen: NSScreen) {
        // Close any existing border window first (synchronously on main thread)
        borderWindow?.orderOut(nil)
        borderWindow = nil

        let borderWidth: CGFloat = 3
        let window = NSWindow(
            contentRect: rect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.level = .screenSaver  // always on top
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.hasShadow = false

        // Border view: red rounded rect outline
        let view = BorderView(frame: NSRect(origin: .zero, size: rect.size), borderWidth: borderWidth)
        window.contentView = view

        // Set window frame explicitly to the recording rect
        window.setFrame(rect, display: false)
        window.orderFrontRegardless()
        borderWindow = window

        print("[SnapPin] Border window shown at \(rect)")
    }

    private func hideBorderWindow() {
        if Thread.isMainThread {
            borderWindow?.orderOut(nil)
            borderWindow = nil
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.borderWindow?.orderOut(nil)
                self?.borderWindow = nil
            }
        }
    }

    // MARK: - Frame handling (called from RecordingStreamOutput)

    func handleFrame(_ sampleBuffer: CMSampleBuffer, sessionID: UUID) {
        guard frameSessionID == sessionID else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard pts.isNumeric else { return }
        let elapsed = firstSampleReceived ? CMTimeGetSeconds(CMTimeSubtract(pts, startTime)) : 0
        guard gifFrames.isEmpty || elapsed - lastFrameTime >= 1.0 / gifFPS else { return }
        guard let croppedBuffer = RecordingFrameCropper.crop(pixelBuffer, to: recordingRect,
                                                             on: recordingScreenFrame) else { return }
        if !firstSampleReceived {
            firstSampleReceived = true
            startTime = pts
        }

        let ciImage = CIImage(cvPixelBuffer: croppedBuffer)
        if let cgImage = imageContext.createCGImage(ciImage, from: ciImage.extent) {
            gifFrames.append((cgImage, elapsed))
            lastFrameTime = elapsed
        }
    }

    // MARK: - Save panel

    private func promptSavePanel() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Save Recording"
        alert.informativeText = "Choose the format to save your recording."
        alert.addButton(withTitle: "Save as MP4")
        alert.addButton(withTitle: "Save as GIF")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            saveAs(.mp4)
        case .alertSecondButtonReturn:
            saveAs(.gif)
        default:
            finishExport(success: false, message: nil)
        }
    }

    private func saveAs(_ format: RecordingFormat) {
        let panel = NSSavePanel()
        let timestamp = Int(Date().timeIntervalSince1970)
        switch format {
        case .mp4:
            panel.allowedContentTypes = [UTType.mpeg4Movie]
            panel.nameFieldStringValue = "SnapPin_\(timestamp).mp4"
        case .gif:
            panel.allowedContentTypes = [UTType.gif]
            panel.nameFieldStringValue = "SnapPin_\(timestamp).gif"
        }
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            finishExport(success: false, message: nil)
            return
        }

        switch format {
        case .mp4:
            encodeMp4(to: url)
        case .gif:
            encodeGif(to: url)
        }
    }

    // MARK: - MP4 encoding

    private func encodeMp4(to url: URL) {
        guard !gifFrames.isEmpty else {
            finishExport(success: false, message: "No frames captured")
            return
        }

        // Use the first frame to determine dimensions
        let firstFrame = gifFrames[0].0
        let width = firstFrame.width
        let height = firstFrame.height

        // Remove existing file
        try? FileManager.default.removeItem(at: url)

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            finishExport(success: false, message: "Failed to create AVAssetWriter")
            return
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let fps: Double = 10
        for (index, (cgImage, elapsed)) in gifFrames.enumerated() {
            let pts = CMTime(seconds: elapsed, preferredTimescale: 600)
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.01)
            }
            if let buffer = pixelBufferFromCGImage(cgImage) {
                adaptor.append(buffer, withPresentationTime: pts)
            }
            _ = fps // suppress warning
            _ = index
        }

        input.markAsFinished()
        writer.finishWriting { [weak self] in
            DispatchQueue.main.async {
                if writer.status == .completed {
                    self?.finishExport(success: true, message: url.path)
                } else {
                    self?.finishExport(success: false, message: writer.error?.localizedDescription ?? "Failed to save MP4")
                }
            }
        }
    }

    private func pixelBufferFromCGImage(_ image: CGImage) -> CVPixelBuffer? {
        let width = image.width
        let height = image.height
        var buffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, attrs as CFDictionary, &buffer)
        guard let pb = buffer else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(pb),
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )
        ctx?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(pb, [])
        return pb
    }

    // MARK: - GIF encoding

    private func encodeGif(to url: URL) {
        guard !gifFrames.isEmpty else {
            finishExport(success: false, message: "No frames captured")
            return
        }

        let fileProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0  // infinite loop
            ]
        ]

        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, gifFrames.count, nil) else {
            finishExport(success: false, message: "Failed to create GIF destination")
            return
        }

        CGImageDestinationSetProperties(dest, fileProperties as CFDictionary)

        // Calculate per-frame delay from timestamps
        for (i, (cgImage, elapsed)) in gifFrames.enumerated() {
            let nextElapsed = i + 1 < gifFrames.count ? gifFrames[i + 1].1 : elapsed + 1.0 / gifFPS
            let delay = nextElapsed - elapsed
            let frameProperties: [String: Any] = [
                kCGImagePropertyGIFDictionary as String: [
                    kCGImagePropertyGIFDelayTime as String: delay
                ]
            ]
            CGImageDestinationAddImage(dest, cgImage, frameProperties as CFDictionary)
        }

        if CGImageDestinationFinalize(dest) {
            finishExport(success: true, message: url.path)
        } else {
            finishExport(success: false, message: "Failed to finalize GIF")
        }
    }

    // MARK: - Status indicator

    private func updateStatusIndicator() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let btn = self.statusButton else { return }
            if self.state.canStop {
                // Red dot overlay on the status bar icon
                btn.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")
                btn.contentTintColor = .systemRed
            } else {
                btn.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "SnapPin")
                btn.contentTintColor = nil
            }
        }
    }
}

// MARK: - Recording format

enum RecordingFormat {
    case mp4
    case gif
}

// MARK: - SCStreamOutput delegate

class RecordingStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    weak var manager: RecordingManager?
    private let sessionID: UUID

    init(sessionID: UUID) { self.sessionID = sessionID }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer),
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int,
              status == SCFrameStatus.complete.rawValue else { return }
        autoreleasepool { manager?.handleFrame(sampleBuffer, sessionID: sessionID) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        manager?.streamFailed(sessionID: sessionID, error: error)
    }
}

// MARK: - Border view for recording indicator

/// A transparent view that draws a red rounded-rect border using Core Graphics.
/// Using draw(_:) ensures the border is always visible regardless of layer backing.
class BorderView: NSView {
    private let borderWidth: CGFloat
    private let borderColor: NSColor = .systemRed
    private let cornerRadius: CGFloat = 4

    init(frame: NSRect, borderWidth: CGFloat) {
        self.borderWidth = borderWidth
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let inset = borderWidth / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        ctx.setStrokeColor(borderColor.cgColor)
        ctx.setLineWidth(borderWidth)
        ctx.addPath(path)
        ctx.strokePath()
    }
}
