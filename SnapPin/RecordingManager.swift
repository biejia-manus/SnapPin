import Cocoa
import AVFoundation
import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Recording state

enum RecordingState {
    case idle
    case recording
}

// MARK: - RecordingManager

class RecordingManager: NSObject {

    static let shared = RecordingManager()

    private(set) var state: RecordingState = .idle

    // Callback invoked on main thread when recording stops (success or failure)
    var onRecordingFinished: ((Bool, String?) -> Void)?

    // Status bar button reference for red-dot indicator (set by AppDelegate)
    var statusButton: NSStatusBarButton?

    // SCStream components
    private var stream: SCStream?
    private var streamOutput: RecordingStreamOutput?

    // Recording region (in screen coordinates, points)
    private var recordingRect: CGRect = .zero
    private var recordingScreen: NSScreen?

    // Red border overlay window shown during recording
    private var borderWindow: NSWindow?

    // AVAssetWriter for MP4
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var outputURL: URL?
    private var outputFormat: RecordingFormat = .mp4

    // GIF frame accumulation
    private var gifFrames: [(CGImage, TimeInterval)] = []
    private var lastFrameTime: TimeInterval = 0
    private let gifFPS: Double = 10   // capture at 10fps for GIF

    // Timing
    private var startTime: CMTime = .zero
    private var firstSampleReceived = false

    // MARK: - Start recording

    func startRecording(rect: CGRect, on screen: NSScreen) {
        guard state == .idle else { return }
        recordingRect = rect
        recordingScreen = screen
        state = .recording
        updateStatusIndicator()

        showBorderWindow(rect: rect, on: screen)

        // Wait a brief moment for the border window to be created on the main thread
        // before querying SCShareableContent, so we can exclude it from the stream.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            self.startStream(rect: rect, screen: screen)
        }
    }

    private func startStream(rect: CGRect, screen: NSScreen) {
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { [weak self] content, error in
            guard let self = self else { return }
            guard let content = content else {
                let msg = "Failed to get screen content: " + (error?.localizedDescription ?? "unknown")
                DispatchQueue.main.async {
                    self.state = .idle
                    self.hideBorderWindow()
                    self.onRecordingFinished?(false, msg)
                }
                return
            }

            // Find the SCDisplay matching the target screen
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0
            guard let scDisplay = content.displays.first(where: { $0.displayID == displayID }) else {
                DispatchQueue.main.async {
                    self.state = .idle
                    self.hideBorderWindow()
                    self.onRecordingFinished?(false, "Could not find display for recording")
                }
                return
            }

            // Exclude the border window from the stream so it doesn't appear in the recording
            var excludedWindows: [SCWindow] = []
            if let borderWin = self.borderWindow {
                let borderWindowID = CGWindowID(borderWin.windowNumber)
                if let scWin = content.windows.first(where: { $0.windowID == borderWindowID }) {
                    excludedWindows.append(scWin)
                }
            }

            let filter = SCContentFilter(display: scDisplay, excludingWindows: excludedWindows)
            let config = SCStreamConfiguration()

            // Use full display resolution, we'll crop in the output handler
            config.width = scDisplay.width * 2
            config.height = scDisplay.height * 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30) // 30fps
            config.showsCursor = true
            config.captureResolution = .best
            config.pixelFormat = kCVPixelFormatType_32BGRA

            let output = RecordingStreamOutput()
            output.manager = self
            self.streamOutput = output
            self.firstSampleReceived = false
            self.gifFrames = []
            self.lastFrameTime = 0

            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            do {
                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "snappin.recording"))
                try stream.startCapture()
                self.stream = stream
                print("[SnapPin] Recording started for rect: \(rect)")
            } catch {
                DispatchQueue.main.async {
                    self.state = .idle
                    self.updateStatusIndicator()
                    self.onRecordingFinished?(false, "Failed to start stream: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Stop recording

    func stopRecording() {
        guard state == .recording else { return }
        state = .idle
        updateStatusIndicator()

        hideBorderWindow()

        stream?.stopCapture { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                print("[SnapPin] Stream stop error: \(error)")
            }
            self.stream = nil
            self.streamOutput = nil

            DispatchQueue.main.async {
                self.promptSavePanel()
            }
        }
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

    func handleFrame(_ sampleBuffer: CMSampleBuffer) {
        guard state == .recording else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if !firstSampleReceived {
            firstSampleReceived = true
            startTime = pts
        }

        // Crop the pixel buffer to the recording rect
        guard let croppedBuffer = cropPixelBuffer(pixelBuffer, to: recordingRect, screen: recordingScreen) else { return }

        // Accumulate for GIF (at reduced frame rate)
        let elapsed = CMTimeGetSeconds(CMTimeSubtract(pts, startTime))
        if elapsed - lastFrameTime >= 1.0 / gifFPS || gifFrames.isEmpty {
            let ciImage = CIImage(cvPixelBuffer: croppedBuffer)
            let context = CIContext()
            if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                gifFrames.append((cgImage, elapsed))
                lastFrameTime = elapsed
            }
        }

        // Write to MP4 asset writer
        if let writer = assetWriter, let input = videoInput, let adaptor = pixelBufferAdaptor {
            if writer.status == .unknown {
                writer.startWriting()
                writer.startSession(atSourceTime: .zero)
            }
            if writer.status == .writing && input.isReadyForMoreMediaData {
                let relPTS = CMTimeSubtract(pts, startTime)
                adaptor.append(croppedBuffer, withPresentationTime: relPTS)
            }
        }
    }

    // MARK: - Crop pixel buffer to recording rect

    private func cropPixelBuffer(_ buffer: CVPixelBuffer, to rect: CGRect, screen: NSScreen?) -> CVPixelBuffer? {
        guard let screen = screen else { return nil }

        let scale = CGFloat(CVPixelBufferGetWidth(buffer)) / screen.frame.width
        let cropX = rect.origin.x * scale
        // In CoreVideo, Y=0 is top; in AppKit, Y=0 is bottom — flip Y
        let cropY = (screen.frame.height - rect.maxY) * scale
        let cropW = rect.width * scale
        let cropH = rect.height * scale

        let cropRect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }

        let bytesPerPixel = 4
        let offsetX = Int(cropRect.origin.x) * bytesPerPixel
        let offsetY = Int(cropRect.origin.y) * Int(bytesPerRow)
        let croppedBase = baseAddress.advanced(by: offsetY + offsetX)

        var croppedBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreateWithBytes(
            kCFAllocatorDefault,
            Int(cropW),
            Int(cropH),
            kCVPixelFormatType_32BGRA,
            croppedBase,
            bytesPerRow,
            nil, nil,
            attrs as CFDictionary,
            &croppedBuffer
        )
        guard status == kCVReturnSuccess else { return nil }
        return croppedBuffer
    }

    // MARK: - Save panel

    private func promptSavePanel() {
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
            onRecordingFinished?(false, nil)
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
            onRecordingFinished?(false, nil)
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
            onRecordingFinished?(false, "No frames captured")
            return
        }

        // Use the first frame to determine dimensions
        let firstFrame = gifFrames[0].0
        let width = firstFrame.width
        let height = firstFrame.height

        // Remove existing file
        try? FileManager.default.removeItem(at: url)

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            onRecordingFinished?(false, "Failed to create AVAssetWriter")
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
                    self?.onRecordingFinished?(true, url.path)
                } else {
                    self?.onRecordingFinished?(false, writer.error?.localizedDescription)
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
            onRecordingFinished?(false, "No frames captured")
            return
        }

        let fileProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0  // infinite loop
            ]
        ]

        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, gifFrames.count, nil) else {
            onRecordingFinished?(false, "Failed to create GIF destination")
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
            onRecordingFinished?(true, url.path)
        } else {
            onRecordingFinished?(false, "Failed to finalize GIF")
        }
    }

    // MARK: - Status indicator

    private func updateStatusIndicator() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let btn = self.statusButton else { return }
            if self.state == .recording {
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

class RecordingStreamOutput: NSObject, SCStreamOutput {
    weak var manager: RecordingManager?

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        manager?.handleFrame(sampleBuffer)
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
