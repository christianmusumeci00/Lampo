import AppKit
import CoreGraphics
import ScreenCaptureKit

/// A screenshot of one window, attached to a question as an image.
struct WindowCapture: Identifiable, Sendable {
    let id = UUID()
    let image: CGImage
    let app: SourceApp
    /// Window title, when the app exposes one.
    let title: String?
}

enum ScreenCaptureError: LocalizedError, Equatable {
    case permissionDenied
    case noWindow
    case failed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return String(localized: "Allow Screen Recording so Lampo can look at the window you're using.")
        case .noWindow:
            return String(localized: "There's no window to look at. Click the window you mean, then try again.")
        case .failed:
            return String(localized: "Couldn't capture the window. Try again.")
        }
    }
}

/// Captures the frontmost window of an app. Mocked in tests.
protocol ScreenCapturing: Sendable {
    func captureFrontWindow(of app: SourceApp) async throws -> WindowCapture
}

/// ScreenCaptureKit implementation. It captures a single window on its own
/// (`desktopIndependentWindow`), so Lampo's panel and Lens never appear in the image,
/// even when they overlap it.
final class ScreenCaptureService: ScreenCapturing {
    /// The longest side of the image sent to the model, in pixels.
    static let maxPixelSide: CGFloat = 1600

    init() {}

    func captureFrontWindow(of app: SourceApp) async throws -> WindowCapture {
        guard CGPreflightScreenCaptureAccess() else { throw ScreenCaptureError.permissionDenied }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            Log.context.error("shareable content failed: \(error.localizedDescription, privacy: .public)")
            throw Self.map(error)
        }

        let candidates = content.windows.filter {
            $0.owningApplication?.processID == app.processIdentifier && $0.windowLayer == 0
                && $0.frame.width >= 80 && $0.frame.height >= 80
        }
        // CGWindowList is ordered front to back; SCShareableContent isn't documented to be.
        let frontID = Self.frontWindowID(pid: app.processIdentifier)
        guard let window = candidates.first(where: { $0.windowID == frontID }) ?? candidates.first else {
            throw ScreenCaptureError.noWindow
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let size = Self.targetSize(points: filter.contentRect.size, scale: CGFloat(filter.pointPixelScale))
        configuration.width = Int(size.width)
        configuration.height = Int(size.height)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true

        do {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            Log.context.debug("captured window \(image.width, privacy: .public)×\(image.height, privacy: .public)")
            return WindowCapture(image: image, app: app, title: window.title)
        } catch {
            Log.context.error("window capture failed: \(error.localizedDescription, privacy: .public)")
            throw Self.map(error)
        }
    }

    /// Pixel size of the capture: native resolution, scaled down so the longest side is at most 1600 px.
    static func targetSize(points: CGSize, scale: CGFloat, maxSide: CGFloat = maxPixelSide) -> CGSize {
        let pixels = CGSize(width: points.width * max(scale, 1), height: points.height * max(scale, 1))
        let longest = max(pixels.width, pixels.height)
        guard longest > 0 else { return .zero }
        let factor = min(1, maxSide / longest)
        return CGSize(width: (pixels.width * factor).rounded(), height: (pixels.height * factor).rounded())
    }

    /// The frontmost normal window of `pid`.
    private static func frontWindowID(pid: pid_t) -> CGWindowID? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let number = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            return number
        }
        return nil
    }

    private static func map(_ error: any Error) -> ScreenCaptureError {
        if let error = error as? SCStreamError, error.code == .userDeclined { return .permissionDenied }
        return CGPreflightScreenCaptureAccess() ? .failed : .permissionDenied
    }
}
