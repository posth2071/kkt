import AppKit
import ApplicationServices
import Foundation
import ImageIO
import Vision

/// Window OCR. Capture is synchronous via `/usr/sbin/screencapture -l <windowNumber>`: ScreenCaptureKit from a
/// command-line process deadlocked waiting for its main-run-loop delivery and CGWindowListCreateImage is
/// unavailable in the current SDK (both measured 2026-11-02).
public enum ScreenText {
    public static func recognize(window: AXUIElement) throws -> [TextBox] {
        guard let position = AXHelpers.position(window), let size = AXHelpers.size(window) else {
            throw KktError.automation(KktConstants.screenCaptureFailedCode)
        }
        let frame = CGRect(origin: position, size: size)
        let image = try capture(frame: frame, title: AXHelpers.title(window))
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = KktConstants.contactRecognitionLanguages
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(KktConstants.contactCandidateCount).first?.string else {
                return nil
            }
            return TextBox(text: text, rect: globalRect(normalized: observation.boundingBox, windowFrame: frame))
        }
    }

    public static func globalRect(normalized: CGRect, windowFrame: CGRect) -> CGRect {
        CGRect(x: windowFrame.minX + normalized.minX * windowFrame.width,
               y: windowFrame.maxY - normalized.maxY * windowFrame.height,
               width: normalized.width * windowFrame.width, height: normalized.height * windowFrame.height)
    }

    /// Window-server bounds and AX frames use the same top-left global coordinates.
    public static func matchesFrame(_ candidate: CGRect, _ target: CGRect) -> Bool {
        abs(candidate.minX - target.minX) <= KktConstants.frameMatchTolerance
            && abs(candidate.minY - target.minY) <= KktConstants.frameMatchTolerance
            && abs(candidate.width - target.width) <= KktConstants.frameMatchTolerance
            && abs(candidate.height - target.height) <= KktConstants.frameMatchTolerance
    }

    private static func capture(frame: CGRect, title: String?) throws -> CGImage {
        guard CGPreflightScreenCaptureAccess() else {
            throw KktError.automation(KktConstants.screenRecordingPermissionCode)
        }
        let windowNumber = try awaitWindowNumber(frame: frame, title: title)
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + KktConstants.captureFileExtension)
        defer { try? FileManager.default.removeItem(at: file) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: KktConstants.screencapturePath)
        process.arguments = KktConstants.screencaptureArguments + [String(windowNumber), file.path]
        try process.run()
        process.waitUntilExit()
        // Read the bytes before the temporary file is removed: CGImageSource decodes lazily, and decoding
        // after deletion yields a blank image (Vision then finds no text — measured 2026-11-02).
        guard process.terminationStatus == KktConstants.systemCallSuccess,
              let data = try? Data(contentsOf: file),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, .zero,
                  [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
            throw KktError.automation(KktConstants.screenCaptureFailedCode)
        }
        return image
    }

    public struct WindowInfo: Equatable {
        public let number: Int
        public let name: String?
        public let bounds: CGRect
        public init(number: Int, name: String?, bounds: CGRect) { self.number = number; self.name = name; self.bounds = bounds }
    }

    /// The main window and a chat window can share the exact same frame (measured 2026-11-02),
    /// so the window-server name must equal the AX title; list order is front to back.
    public static func pickWindow(_ windows: [WindowInfo], frame: CGRect, title: String?) -> Int? {
        let framed = windows.filter { matchesFrame($0.bounds, frame) }
        guard let title, !title.isEmpty else { return framed.first?.number }
        return framed.first(where: { $0.name == title })?.number
    }

    /// A just-opened window can be listed before the window server knows its name; retry briefly.
    private static func awaitWindowNumber(frame: CGRect, title: String?) throws -> Int {
        let deadline = Date().addingTimeInterval(KktConstants.windowLookupTimeout)
        while true {
            do { return try findWindowNumber(frame: frame, title: title) } catch {
                guard Date() < deadline else { throw error }
                Thread.sleep(forTimeInterval: KktConstants.windowPoll)
            }
        }
    }

    private static func findWindowNumber(frame: CGRect, title: String?) throws -> Int {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: KakaoApp.bundleId)
            .first?.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { throw KktError.automation(KktConstants.contactWindowMissingCode) }
        let windows = list.compactMap { info -> WindowInfo? in
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  let number = info[kCGWindowNumber as String] as? Int else { return nil }
            return WindowInfo(number: number, name: info[kCGWindowName as String] as? String, bounds: rect)
        }
        guard let number = pickWindow(windows, frame: frame, title: title) else {
            throw KktError.automation(KktConstants.contactWindowMissingCode)
        }
        return number
    }
}
