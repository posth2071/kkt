import AppKit
import CoreGraphics

public final class FocusGuard {
    private let previousBundleId: String?
    private let mouseLocation: CGPoint?
    private let currentApplication: () -> String?
    private let run: (String, [String]) -> Void
    private let restoreCursor: (CGPoint) -> Void

    public init(
        restoresCursor: Bool = false,
        captureApplication: () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier },
        captureCursor: () -> CGPoint? = { CGEvent(source: nil)?.location },
        currentApplication: @escaping () -> String? = KakaoApp.frontmostBundleId,
        run: @escaping (String, [String]) -> Void = { path, arguments in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            if (try? process.run()) != nil { process.waitUntilExit() }
        }, restoreCursor: @escaping (CGPoint) -> Void = {
            CGWarpMouseCursorPosition($0)
            CGAssociateMouseAndMouseCursorPosition(KktConstants.associateMouseCursor)
        }
    ) {
        previousBundleId = captureApplication()
        mouseLocation = restoresCursor ? captureCursor() : nil
        self.currentApplication = currentApplication
        self.run = run
        self.restoreCursor = restoreCursor
    }

    public func restore() {
        if let previousBundleId,
           Self.shouldRestore(previousBundleId: previousBundleId, currentBundleId: currentApplication()) {
            let command = Self.restoreCommand(bundleId: previousBundleId)
            run(command.path, command.args)
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
