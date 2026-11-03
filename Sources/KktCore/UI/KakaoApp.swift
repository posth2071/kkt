import AppKit
import ApplicationServices

public enum KakaoApp {
    public static let bundleId = KktConstants.AX.bundleId

    public static func frontmostBundleId() -> String? {
        var application: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(),
            kAXFocusedApplicationAttribute as CFString, &application) == .success,
              let application, CFGetTypeID(application) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeDowncast(application, to: AXUIElement.self)
        var pid: pid_t = .zero
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    public static func checkNotInUse(frontmostBundleId: () -> String? = frontmostBundleId) throws {
        guard frontmostBundleId() != bundleId else { throw KktError.kakaoInUse }
    }

    public static func runningPid() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .first(where: { !$0.isTerminated })?.processIdentifier
    }
}
