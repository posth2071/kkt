import ApplicationServices
import Foundation

public enum AXHelpers {
    public static func attribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    public static func children(_ element: AXUIElement) -> [AXUIElement] {
        elements(element, attribute: kAXChildrenAttribute as String) ?? []
    }

    public static func windows(_ app: AXUIElement) -> [AXUIElement] {
        elements(app, attribute: kAXWindowsAttribute as String) ?? []
    }

    static func elements(_ element: AXUIElement, attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? [AXUIElement]
    }

    public static func role(_ element: AXUIElement) -> String? { attribute(element, kAXRoleAttribute as String) }
    public static func title(_ element: AXUIElement) -> String? { attribute(element, kAXTitleAttribute as String) }
    public static func value(_ element: AXUIElement) -> String? { attribute(element, kAXValueAttribute as String) }
    public static func description(_ element: AXUIElement) -> String? { attribute(element, kAXDescriptionAttribute as String) }
    public static func identifier(_ element: AXUIElement) -> String? { attribute(element, kAXIdentifierAttribute as String) }

    public static func position(_ element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    public static func size(_ element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    public static func setValue(_ element: AXUIElement, _ value: String) -> Bool {
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFTypeRef) == .success
    }

    public static func performAction(_ element: AXUIElement, _ action: String) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }

    public static func focus(_ element: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success
    }

    public static func closeWindow(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return false }
        return performAction(value as! AXUIElement, kAXPressAction as String)
    }

    public static func selectRow(_ row: AXUIElement, in table: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(table, kAXSelectedRowsAttribute as CFString, [row] as CFArray) == .success
    }

    public static func findAll(_ element: AXUIElement, role targetRole: String) -> [AXUIElement] {
        findAll(element, role: targetRole, maxDepth: KktConstants.AX.searchDepth)
    }

    public static func findAll(_ element: AXUIElement, role targetRole: String,
                               maxDepth: Int) -> [AXUIElement] {
        guard maxDepth >= KktConstants.zero else { return [] }
        let role = role(element)
        let matches = role == targetRole ? [element] : []
        guard role != KktConstants.AX.cell, role != KktConstants.AX.table else { return matches }
        return matches + children(element).flatMap {
            findAll($0, role: targetRole, maxDepth: maxDepth - KktConstants.one)
        }
    }
}
