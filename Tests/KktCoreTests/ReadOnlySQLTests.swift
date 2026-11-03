import XCTest
@testable import KktCore

final class ReadOnlySQLTests: XCTestCase {
    func testReadOnlySqlRejectsWrites() throws {
        for sql in ["DELETE FROM NTChatMessage", "SELECT 1; DROP TABLE NTChatMessage", "ATTACH 'other.db' AS other"] {
            XCTAssertThrowsError(try ReadOnlySQL.validate(sql)) {
                XCTAssertEqual($0 as? KktError, .readOnlySQL)
                XCTAssertEqual(($0 as? KktError)?.code, "read_only_sql")
            }
        }
        XCTAssertNoThrow(try ReadOnlySQL.validate("WITH x AS (SELECT 1) SELECT * FROM x"))
    }

    func testReadOnlySqlHandlesCommentsQuotesAndTrailingSemicolon() throws {
        for sql in ["  -- comment\nSELECT 1; -- end", "/* comment */ SELECT ';'", "PRAGMA table_info(NTChatRoom)",
                    "SELECT \"a;b\", 'it''s;fine', `a;b`, [a;b] /* ; */;", "select 1", "SELECT 1 /* comment */"] {
            XCTAssertNoThrow(try ReadOnlySQL.validate(sql), sql)
        }
        for sql in ["", "-- only a comment", "/* unterminated", "SELECT 1; SELECT 2", "SELECT 1;;",
                    "SELECT 'unterminated", "SELECT 1; /* c */ ATTACH 'x' AS x", "SELECTED 1", "SELECT 1\0; DELETE FROM x"] {
            XCTAssertThrowsError(try ReadOnlySQL.validate(sql), sql) {
                XCTAssertEqual($0 as? KktError, .readOnlySQL)
            }
        }
    }
}
