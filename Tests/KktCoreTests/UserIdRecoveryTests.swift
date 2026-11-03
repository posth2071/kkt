import CommonCrypto
import XCTest
@testable import KktCore

final class UserIdRecoveryTests: XCTestCase {
    func testRecoverFindsUserId() {
        XCTAssertEqual(UserIdRecovery.recover(sha512Hex: hash("12345"), range: 1...20000, workers: 4), 12345)
    }

    func testRecoverMissingHashReturnsNil() {
        XCTAssertNil(UserIdRecovery.recover(sha512Hex: hash("20001"), range: 1...20000, workers: 4))
    }

    func testRecoverRejectsMalformedHash() {
        XCTAssertNil(UserIdRecovery.recover(sha512Hex: "invalid", range: 1...10, workers: 4))
    }

    func testActiveAccountHashUsesDenyFileExtensionPrefix() {
        let expected = hash("12345")
        XCTAssertEqual(DeviceInfo.activeAccountHash(from: [UserIdRecovery.plistKeyPrefix + expected: 1]), expected)
        XCTAssertNil(DeviceInfo.activeAccountHash(from: [UserIdRecovery.plistKeyPrefix + hash("0"): 1]))
        XCTAssertNil(DeviceInfo.activeAccountHash(from: [UserIdRecovery.plistKeyPrefix + expected: 0]))
    }

    private func hash(_ value: String) -> String {
        let data = Array(value.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
        CC_SHA512(data, CC_LONG(data.count), &digest)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
