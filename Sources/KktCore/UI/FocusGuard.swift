import AppKit
import CoreGraphics

public final class FocusGuard {
    private let previousBundleId: String?
    private let previousProcess: pid_t?
    private let mouseLocation: CGPoint?
    private let currentApplication: () -> String?
    private let run: (String, [String]) -> Void
    private let activate: (pid_t) -> Void
    private let restoreCursor: (CGPoint) -> Void

    public init(
        restoresCursor: Bool = false,
        captureApplication: () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier },
        captureProcess: () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
        captureCursor: () -> CGPoint? = { CGEvent(source: nil)?.location },
        currentApplication: @escaping () -> String? = KakaoApp.frontmostBundleId,
        run: @escaping (String, [String]) -> Void = { path, arguments in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            if (try? process.run()) != nil { process.waitUntilExit() }
        }, activate: @escaping (pid_t) -> Void = { SkyLightFocus.bringToFront(pid: $0) },
        restoreCursor: @escaping (CGPoint) -> Void = {
            CGWarpMouseCursorPosition($0)
            CGAssociateMouseAndMouseCursorPosition(KktConstants.associateMouseCursor)
        }
    ) {
        previousBundleId = captureApplication()
        previousProcess = captureProcess()
        mouseLocation = restoresCursor ? captureCursor() : nil
        self.currentApplication = currentApplication
        self.run = run
        self.activate = activate
        self.restoreCursor = restoreCursor
    }

    public func restore() {
        if let previousBundleId,
           Self.shouldRestore(previousBundleId: previousBundleId, currentBundleId: currentApplication()) {
            let command = Self.restoreCommand(bundleId: previousBundleId)
            run(command.path, command.args)
        } else if previousBundleId == nil, let previousProcess, currentApplication() == KakaoApp.bundleId {
            // Apps without a bundle, such as the Android emulator, cannot be reopened with `open -b`.
            activate(previousProcess)
        }
        if let mouseLocation { restoreCursor(mouseLocation) }
    }

    public static func shouldRestore(previousBundleId: String?, currentBundleId: String?) -> Bool {
        guard let previousBundleId, previousBundleId != KakaoApp.bundleId else { return false }
        return currentBundleId == KakaoApp.bundleId
    }

    public static func restoreCommand(bundleId: String) -> (path: String, args: [String]) {
        (KktConstants.restoreOpenPath, [KktConstants.restoreBundleArgument, bundleId])
    }
}
