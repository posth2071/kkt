import ApplicationServices
import XCTest
@testable import KktCore

final class ChatSearchTests: XCTestCase {
    func testSearchRestoreKeepsEmptyAndKoreanText() throws {
        let empty = Effects(original: "")
        let emptySearch = try XCTUnwrap(empty.makeSearch())
        emptySearch.restore()
        XCTAssertEqual(empty.text, "")
        XCTAssertEqual(empty.clears, 0)
        XCTAssertEqual(empty.typed, [])

        let korean = Effects(original: "모집 검색")
        let koreanSearch = try XCTUnwrap(korean.makeSearch())
        XCTAssertTrue(koreanSearch.clear())
        koreanSearch.type("다른 검색")
        koreanSearch.restore()
        XCTAssertEqual(korean.text, "모집 검색")
        XCTAssertEqual(korean.clears, 2)
        XCTAssertEqual(korean.typed, ["다른 검색", "모집 검색"])
    }

    func testSearchOpensAndClosesHiddenField() throws {
        let hidden = Effects(original: "", visible: false)
        let search = try XCTUnwrap(hidden.makeSearch())
        XCTAssertTrue(search.openedByKkt)
        XCTAssertEqual(hidden.presses, 1)
        search.type("모집 검색")
        search.restore()
        XCTAssertEqual(hidden.text, "")
        XCTAssertEqual(hidden.presses, 2)
        XCTAssertFalse(hidden.visible)
        search.restore()
        XCTAssertEqual(hidden.presses, 2)

        let visible = Effects(original: "모집 검색")
        let visibleSearch = try XCTUnwrap(visible.makeSearch())
        XCTAssertFalse(visibleSearch.openedByKkt)
        XCTAssertTrue(visibleSearch.clear())
        visibleSearch.restore()
        XCTAssertEqual(visible.text, "모집 검색")
        XCTAssertEqual(visible.presses, 0)
        XCTAssertTrue(visible.visible)
    }

    func testFailedClearDoesNotAppendOriginalText() throws {
        let effects = Effects(original: "모집 검색")
        let search = try XCTUnwrap(effects.makeSearch())
        effects.text = "다른 검색"
        effects.canClear = false
        search.restore()
        XCTAssertEqual(effects.typed, [])
    }

    private final class Effects {
        let field = AXUIElementCreateApplication(-1)
        var text: String
        var visible: Bool
        var presses = 0
        var clears = 0
        var typed: [String] = []
        var canClear = true

        init(original: String, visible: Bool = true) {
            text = original
            self.visible = visible
        }

        func makeSearch() -> ChatSearch? {
            ChatSearch(findField: { self.visible ? self.field : nil }, pressSearch: {
                self.presses += 1
                self.visible.toggle()
                return true
            }, read: { _ in self.text }, clear: { _ in
                self.clears += 1
                guard self.canClear else { return false }
                self.text = ""
                return true
            }, type: { _, text in
                self.typed.append(text)
                self.text += text
            }, sleep: { _ in })
        }
    }

    func testClearButtonMatchesDescriptionWhenTitleIsEmpty() {
        XCTAssertTrue(ChatSearch.isClearButton(role: "AXButton", title: "", description: "취소"))
        XCTAssertTrue(ChatSearch.isClearButton(role: "AXButton", title: "취소", description: nil))
        XCTAssertFalse(ChatSearch.isClearButton(role: "AXButton", title: "", description: "검색"))
        XCTAssertFalse(ChatSearch.isClearButton(role: "AXStaticText", title: nil, description: "취소"))
    }
}
