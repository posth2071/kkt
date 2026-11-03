import ApplicationServices
import Foundation

public enum AXIdentifierTable {
    public struct Element {
        public let role: String
        public let identifier: String?
        public let title: String?
        public let description: String?
        public let value: String?

        public init(role: String, identifier: String? = nil, title: String? = nil,
                    description: String? = nil, value: String? = nil) {
            self.role = role
            self.identifier = identifier
            self.title = title
            self.description = description
            self.value = value
        }
    }

    public struct Snapshot {
        public let windows: [WindowInfo]
        public let elements: [Element]

        public init(windows: [WindowInfo], elements: [Element]) {
            self.windows = windows
            self.elements = elements
        }
    }

    private struct Requirement {
        let name: String
        let role: String
        var identifier: String?
        var description: String?
        var titlePrefix: String?

        func matches(_ element: Element) -> Bool {
            element.role == role
                && (identifier == nil || element.identifier == identifier)
                && (description == nil || element.description == description)
                && (titlePrefix == nil || element.title?.hasPrefix(titlePrefix!) == true)
        }
    }

    public static func missing(in snapshot: Snapshot) -> [String] {
        typealias C = KktConstants.DoctorAX
        var requirements = mainRequirements
        if snapshot.elements.contains(where: { $0.role == KktConstants.AX.row }) {
            requirements += rowRequirements
        }
        if snapshot.elements.contains(where: { $0.identifier == C.chatWindow })
            || snapshot.windows.contains(where: { $0.identifier == C.chatWindow }) {
            requirements += chatRequirements
        }
        if snapshot.elements.contains(where: {
            $0.role == KktConstants.AX.textField && $0.value?.isEmpty == false
        }) {
            requirements.append(.init(name: KktConstants.searchClearButtonTitle, role: KktConstants.AX.button,
                                      description: KktConstants.searchClearButtonTitle))
        }
        return requirements.filter { requirement in
            !snapshot.elements.contains(where: requirement.matches)
        }.map(\.name)
    }

    private static var mainRequirements: [Requirement] {
        typealias C = KktConstants.DoctorAX
        return [
            .init(name: KktConstants.mainWindowIdentifier, role: C.window, identifier: KktConstants.mainWindowIdentifier),
            .init(name: C.friends, role: KktConstants.AX.button, identifier: C.friends),
            .init(name: KktConstants.AX.chatrooms, role: KktConstants.AX.button, identifier: KktConstants.AX.chatrooms),
            .init(name: C.more, role: KktConstants.AX.button, identifier: C.more),
            .init(name: KktConstants.AX.chatList, role: KktConstants.AX.table, identifier: KktConstants.AX.chatList),
            .init(name: KktConstants.searchButtonDescription, role: KktConstants.AX.button,
                  description: KktConstants.searchButtonDescription),
        ]
    }

    private static var rowRequirements: [Requirement] {
        typealias C = KktConstants.DoctorAX
        return [
            .init(name: C.rowName, role: KktConstants.AX.staticText, identifier: C.rowName),
            .init(name: C.memberCount, role: KktConstants.AX.staticText, identifier: C.memberCount),
            .init(name: C.rowTime, role: KktConstants.AX.staticText, identifier: C.rowTime),
            .init(name: C.rowImage, role: KktConstants.AX.image, identifier: C.rowImage),
            .init(name: C.rowButton, role: KktConstants.AX.button, identifier: C.rowButton),
        ]
    }

    private static var chatRequirements: [Requirement] {
        typealias C = KktConstants.DoctorAX
        return [
            .init(name: C.chatWindow, role: C.window, identifier: C.chatWindow),
            .init(name: C.messageScroll, role: KktConstants.AX.scrollArea, identifier: C.messageScroll),
            .init(name: C.messageTable, role: KktConstants.AX.table, identifier: C.messageTable),
            .init(name: C.chatTitle, role: KktConstants.AX.staticText, identifier: C.chatTitle),
            .init(name: C.inputScroll, role: KktConstants.AX.scrollArea, identifier: C.inputScroll),
            .init(name: C.input, role: C.textArea, identifier: C.input, description: C.inputDescription),
            .init(name: C.send, role: KktConstants.AX.button, titlePrefix: C.send),
            .init(name: C.members, role: KktConstants.AX.button, titlePrefix: C.members),
            .init(name: C.roomIcon, role: KktConstants.AX.image, identifier: C.roomIcon),
        ]
    }

    static func observe(pid: pid_t) -> Snapshot? {
        let application = AXUIElementCreateApplication(pid)
        guard let windows = AXHelpers.elements(application, attribute: kAXWindowsAttribute as String) else { return nil }
        return Snapshot(windows: windows.map {
            WindowInfo(identifier: AXHelpers.identifier($0), title: AXHelpers.title($0))
        }, elements: windows.filter {
            [KktConstants.mainWindowIdentifier, KktConstants.DoctorAX.chatWindow].contains(AXHelpers.identifier($0))
        }.flatMap { collect($0, depth: KktConstants.zero) })
    }

    private static func collect(_ element: AXUIElement, depth: Int) -> [Element] {
        guard depth <= KktConstants.AX.searchDepth else { return [] }
        let role = AXHelpers.role(element) ?? KktConstants.emptyText
        let info = Element(role: role, identifier: AXHelpers.identifier(element), title: AXHelpers.title(element),
                           description: AXHelpers.description(element),
                           value: role == KktConstants.AX.textField ? AXHelpers.value(element) : nil)
        let children: [AXUIElement]
        if role == KktConstants.AX.table {
            guard info.identifier == KktConstants.AX.chatList else { return [info] }
            children = AXHelpers.elements(element, attribute: kAXVisibleRowsAttribute as String) ?? AXHelpers.children(element)
        } else if role == KktConstants.AX.cell {
            children = AXHelpers.children(element).filter {
                [KktConstants.AX.staticText, KktConstants.AX.image, KktConstants.AX.button].contains(AXHelpers.role($0))
            }
        } else {
            children = AXHelpers.children(element)
        }
        return [info] + children.flatMap { collect($0, depth: depth + KktConstants.one) }
    }
}

extension KktConstants {
    enum DoctorAX {
        static let window = "AXWindow"
        static let textArea = "AXTextArea"
        static let friends = "friends"
        static let more = "more"
        static let rowName = "_NS:40"
        static let memberCount = "Count Label"
        static let rowTime = "_NS:69"
        static let rowImage = "_NS:18"
        static let rowButton = "_NS:11"
        static let chatWindow = "_NS:443"
        static let messageScroll = "_NS:29"
        static let messageTable = "_NS:33"
        static let chatTitle = "_NS:144"
        static let inputScroll = "_NS:47"
        static let input = "_NS:51"
        static let inputDescription = "메시지 입력"
        static let send = "전송"
        static let members = "대화상대 "
        static let roomIcon = "_NS:98"
    }
}
