import ApplicationServices

extension AXHelpers {
    public static func chatListRows(_ table: AXUIElement) -> [AXUIElement] {
        chatListRows(visibleRows: {
            elements(table, attribute: kAXVisibleRowsAttribute as String)
        }, children: { [] })
    }

    static func chatListRows<Row>(visibleRows: () -> [Row]?, children: () -> [Row]) -> [Row] {
        visibleRows() ?? children()
    }

    public static func chatName(inCell cell: AXUIElement) -> String? {
        let texts = children(cell).filter { role($0) == KktConstants.AX.staticText }
        for identifier in KktConstants.AX.chatNameLabels {
            if let label = texts.first(where: { Self.identifier($0) == identifier }),
               let name = value(label), !name.isEmpty { return name }
        }
        return nil
    }

    public static func chatroomsTab(_ window: AXUIElement) -> AXUIElement? {
        if let tab = children(window).first(where: { identifier($0) == KktConstants.AX.chatrooms }) { return tab }
        return [KktConstants.AX.button, KktConstants.AX.checkBox].lazy.flatMap {
            findAll(window, role: $0, maxDepth: KktConstants.AX.tabDepth)
        }.first(where: { identifier($0) == KktConstants.AX.chatrooms })
    }

    public static func chatListTable(_ window: AXUIElement) -> AXUIElement? {
        let tables = children(window).filter { role($0) == KktConstants.AX.scrollArea }.flatMap { area in
            children(area).filter { role($0) == KktConstants.AX.table }
        }
        return tables.first(where: { identifier($0) == KktConstants.AX.chatList })
            ?? tables.max { chatListRows($0).count < chatListRows($1).count }
    }

    static func matchingChatRows(_ table: AXUIElement, name: String, selfChat: Bool) -> [AXUIElement] {
        chatListRows(table).filter { row in
            guard role(row) == KktConstants.AX.row else { return false }
            return children(row).filter { role($0) == KktConstants.AX.cell }.contains { cell in
                if !selfChat { return chatName(inCell: cell) == name }
                return children(cell).contains {
                    role($0) == KktConstants.AX.image
                        && (description($0) ?? KktConstants.emptyText).contains(KktConstants.AX.selfBadge)
                }
            }
        }
    }
}
