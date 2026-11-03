import CommonCrypto
import Foundation

public enum UserIdRecovery {
    public static let plistKeyPrefix = KktConstants.Crypto.plistPrefix

    public static func recover(sha512Hex: String, range: ClosedRange<Int>, workers: Int) -> Int? {
        guard sha512Hex.count == KktConstants.Crypto.hashHexLength,
              range.lowerBound >= KktConstants.zero else { return nil }
        let characters = Array(sha512Hex)
        var target: [UInt8] = []
        for index in stride(from: KktConstants.zero, to: characters.count, by: KktConstants.hexByteWidth) {
            guard let byte = UInt8(String(characters[index..<index + KktConstants.hexByteWidth]), radix: KktConstants.hexRadix) else {
                return nil
            }
            target.append(byte)
        }
        let distance = range.upperBound - range.lowerBound
        guard distance < Int.max else { return nil }
        let count = distance + KktConstants.one
        let workerCount = min(max(workers, KktConstants.one), count)
        let targetBytes = target
        let result = RecoveryResult()
        DispatchQueue.concurrentPerform(iterations: workerCount) { worker in
            let baseCount = count / workerCount
            let remainder = count % workerCount
            let start = range.lowerBound + worker * baseCount + min(worker, remainder)
            let length = baseCount + (worker < remainder ? KktConstants.one : KktConstants.zero)
            var digest = [UInt8](repeating: UInt8(KktConstants.zero), count: Int(CC_SHA512_DIGEST_LENGTH))
            for offset in KktConstants.zero..<length {
                if offset % KktConstants.Crypto.recoveryCheckInterval == KktConstants.zero, result.value != nil { return }
                let candidate = start + offset
                let data = Array(String(candidate).utf8)
                CC_SHA512(data, CC_LONG(data.count), &digest)
                if digest == targetBytes {
                    result.store(candidate)
                    return
                }
            }
        }
        return result.value
    }
}

private final class RecoveryResult: @unchecked Sendable {
    private let lock = NSLock()
    private var recovered: Int?

    var value: Int? { lock.withLock { recovered } }

    func store(_ value: Int) {
        lock.withLock { recovered = value }
    }
}
