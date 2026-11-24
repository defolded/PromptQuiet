import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

enum ScreenCaptureBackendError: LocalizedError {
    case permissionRequired
    case noDisplayAvailable

    var errorDescription: String? {
        switch self {
        case .permissionRequired:
            return "Screen Recording permission required. Grant access in System Settings > Privacy & Security."
        case .noDisplayAvailable:
            return "No active display available for ScreenCaptureKit."
        }
    }
}

private final class DummyStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        // Intentionally discard frames; maintaining an active 2x2 stream triggers macOS sharing suppression.
    }
}

/// Official Apple API alternative using a 2x2 @ 1fps ScreenCaptureKit stream.
/// Shows a small purple indicator in the menu bar while active and requires
/// "Allow notifications when mirroring or sharing the display" to be OFF in System Settings.
@MainActor
final class ScreenCaptureStreamBackend: NotificationSuppressor {
    private var stream: SCStream?
    private let outputQueue = DispatchQueue(label: "com.promptquiet.scstream")
    private let outputHandler = DummyStreamOutput()

    private(set) var isActive = false
    private(set) var statusDetail: String?

    func suppress() async throws {
        if isActive {
            return
        }

        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
            let error = ScreenCaptureBackendError.permissionRequired
            statusDetail = error.errorDescription
            throw error
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else {
                let error = ScreenCaptureBackendError.noDisplayAvailable
                statusDetail = error.errorDescription
                throw error
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            // Even 2x2 dimensions avoid VideoToolbox/IOSurface odd-dimension rejections on Apple Silicon.
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            config.queueDepth = 1
            config.showsCursor = false

            let newStream = SCStream(filter: filter, configuration: config, delegate: outputHandler)
            try newStream.addStreamOutput(outputHandler, type: .screen, sampleHandlerQueue: outputQueue)
            try await newStream.startCapture()

            self.stream = newStream
            self.isActive = true
            self.statusDetail = nil
        } catch {
            self.stream = nil
            self.isActive = false
            self.statusDetail = error.localizedDescription
            throw error
        }
    }

    func resume() async {
        guard let activeStream = stream else {
            isActive = false
            return
        }
        stream = nil
        isActive = false
        try? await activeStream.stopCapture()
    }

    func emergencyResumeSync() {
        guard let activeStream = stream else {
            isActive = false
            return
        }
        stream = nil
        isActive = false
        Task {
            try? await activeStream.stopCapture()
        }
    }
}
