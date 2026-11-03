import XCTest
@testable import KktCore

final class KeyDerivationTests: XCTestCase {
    func testSecureKeyMatchesWrapperVector() {
        XCTAssertEqual(
            KeyDerivation.secureKey(userId: 12345, uuid: "00000000-1111-2222-3333-444444444444"),
            "f42234922325aae6c87f62cb8851f320fb985d16a6bd8e084146ab9274d46aed1616af61aa17706568e4b99077446717f33516d5cd4fa3aef42a74ff7c7e0fa6e52babef318bc1afed1f18666c075e66902b34efb210ea58dee655416381b8af3234dbe6b150dcbe051133045a4cbe21101566785b033c343a99d3456f7bbec5"
        )
    }

    func testDatabaseNameDeterministic() {
        let uuid = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        let first = KeyDerivation.databaseName(userId: 12345, uuid: uuid)
        XCTAssertEqual(first, KeyDerivation.databaseName(userId: 12345, uuid: uuid))
        XCTAssertEqual(first.count, 78)
    }
}
