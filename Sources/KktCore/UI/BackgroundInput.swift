import ApplicationServices
import Foundation

public enum BackgroundInput {
    public static func pressReturn(pid: pid_t) {
        press(keyCode: KktConstants.returnKeyCode, pid: pid)
    }

    public static func press(keyCode: CGKeyCode, flags: CGEventFlags = [], pid: pid_t) {
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        down.postToPid(pid)
        up.postToPid(pid)
    }

    /// Types into whatever element has focus inside the target process, one UTF-16 unit per key event.
    public static func typeText(_ text: String, pid: pid_t,
                                sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }) {
        guard let source = CGEventSource(stateID: .privateState) else { return }
        for unit in text.utf16 {
            var character = unit
            for isDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: KktConstants.unicodeKeyCode,
                                          keyDown: isDown) else { continue }
                event.keyboardSetUnicodeString(stringLength: KktConstants.singleUnit, unicodeString: &character)
                event.postToPid(pid)
            }
            sleep(KktConstants.typeInterval)
        }
    }

    public static func setText(_ element: AXUIElement, _ text: String) -> Bool {
        AXHelpers.setValue(element, text) && matchesReadBack(AXHelpers.value(element), expected: text)
    }

    public static func matchesReadBack(_ actual: String?, expected: String) -> Bool {
        guard let actual else { return false }
        return normalize(actual) == normalize(expected)
    }

    private static func normalize(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: KktConstants.normalizedSpace)
    }
}
