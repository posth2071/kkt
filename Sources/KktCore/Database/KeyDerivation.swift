import CommonCrypto
import Foundation

public enum KeyDerivation {

    static func pbkdf2(password: Data, salt: Data) -> Data {
        let keyLength = KktConstants.Crypto.keyLength
        var derivedKey = Data(count: keyLength)
        _ = derivedKey.withUnsafeMutableBytes { derivedKeyPtr in
            password.withUnsafeBytes { passwordPtr in
                salt.withUnsafeBytes { saltPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordPtr.baseAddress?.assumingMemoryBound(to: Int8.self),
                        password.count,
                        saltPtr.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        KktConstants.Crypto.iterations,
                        derivedKeyPtr.bindMemory(to: UInt8.self).baseAddress,
                        keyLength
                    )
                }
            }
        }
        return derivedKey
    }

    static func hashedDeviceUUID(_ uuid: String) -> String {
        let data = Data(uuid.utf8)
        var sha1 = Data(count: Int(CC_SHA1_DIGEST_LENGTH))
        var sha256 = Data(count: Int(CC_SHA256_DIGEST_LENGTH))

        _ = sha1.withUnsafeMutableBytes { sha1Ptr in
            data.withUnsafeBytes { dataPtr in
                CC_SHA1(dataPtr.baseAddress, CC_LONG(data.count), sha1Ptr.bindMemory(to: UInt8.self).baseAddress)
            }
        }
        _ = sha256.withUnsafeMutableBytes { sha256Ptr in
            data.withUnsafeBytes { dataPtr in
                CC_SHA256(dataPtr.baseAddress, CC_LONG(data.count), sha256Ptr.bindMemory(to: UInt8.self).baseAddress)
            }
        }

        return (sha1 + sha256).base64EncodedString()
    }

    public static func databaseName(userId: Int, uuid: String) -> String {
        let hawawa = [KktConstants.Crypto.dot, KktConstants.Crypto.separator, String(userId), KktConstants.Crypto.first, KktConstants.Crypto.separator,
                      String(uuid.reversed()), KktConstants.Crypto.dot, KktConstants.Crypto.pipe].joined(separator: KktConstants.Crypto.dot)
        let salt = String(hashedDeviceUUID(uuid).reversed())
        let derived = pbkdf2(
            password: Data(hawawa.utf8),
            salt: Data(salt.utf8)
        )
        let hex = derived.map { String(format: KktConstants.hexFormat, $0) }.joined()
        let start = hex.index(hex.startIndex, offsetBy: KktConstants.Crypto.databaseNameOffset)
        let end = hex.index(start, offsetBy: KktConstants.Crypto.databaseNameLength)
        return String(hex[start..<end])
    }

    public static func secureKey(userId: Int, uuid: String) -> String {
        let hashed = hashedDeviceUUID(uuid)
        let parts = [KktConstants.Crypto.first, hashed, KktConstants.Crypto.pipe, KktConstants.Crypto.separator, String(uuid.prefix(KktConstants.Crypto.uuidPrefixLength)),
                     KktConstants.Crypto.marker, String(userId), KktConstants.Crypto.pipe, String(uuid.dropFirst(KktConstants.Crypto.uuidDropLength))]
        let hawawa = parts.joined(separator: KktConstants.Crypto.separator)
        let saltStart = uuid.index(uuid.startIndex, offsetBy: Int(Double(uuid.count) * KktConstants.Crypto.saltRatio))
        let salt = String(uuid[saltStart...])
        let derived = pbkdf2(
            password: Data(String(hawawa.reversed()).utf8),
            salt: Data(salt.utf8)
        )
        return derived.map { String(format: KktConstants.hexFormat, $0) }.joined()
    }
}
