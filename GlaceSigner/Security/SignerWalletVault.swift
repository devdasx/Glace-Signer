import CryptoKit
import Foundation
import Security

enum SignerWalletVaultError: Error, Equatable {
    case encryptionFailed
    case invalidPasscode
    case keychainFailure(OSStatus)
}

enum SignerWalletVault {
    private static let service = "com.devdasx.glace.signer.wallet"
    private static let account = "primary"
    private static let derivationRounds: UInt32 = 210_000

    static func save(
        _ source: SignerSecretSource,
        passcode: String
    ) throws {
        let encodedSource = try JSONEncoder().encode(source)
        let envelope = try seal(encodedSource, passcode: passcode)
        let encodedEnvelope = try JSONEncoder().encode(envelope)

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData] = encodedEnvelope
        attributes[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SignerWalletVaultError.keychainFailure(status)
        }
    }

    static func load(passcode: String) throws -> SignerSecretSource {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw SignerWalletVaultError.keychainFailure(status)
        }

        let envelope = try JSONDecoder().decode(EncryptedEnvelope.self, from: data)
        let sourceData = try open(envelope, passcode: passcode)
        return try JSONDecoder().decode(SignerSecretSource.self, from: sourceData)
    }

    static func delete() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func seal(
        _ plaintext: Data,
        passcode: String
    ) throws -> EncryptedEnvelope {
        let salt = try BitcoinEncoding.randomBytes(count: 16)
        let keyData = try BitcoinEncoding.pbkdf2SHA512(
            password: passcode,
            salt: salt.base64EncodedString(),
            rounds: derivationRounds,
            outputLength: 32
        )
        let sealedBox = try AES.GCM.seal(
            plaintext,
            using: SymmetricKey(data: keyData)
        )
        return EncryptedEnvelope(
            version: 1,
            salt: salt,
            nonce: sealedBox.nonce.withUnsafeBytes { Data($0) },
            ciphertext: sealedBox.ciphertext,
            tag: sealedBox.tag
        )
    }

    static func open(
        _ envelope: EncryptedEnvelope,
        passcode: String
    ) throws -> Data {
        guard envelope.version == 1 else {
            throw SignerWalletVaultError.encryptionFailed
        }
        let keyData = try BitcoinEncoding.pbkdf2SHA512(
            password: passcode,
            salt: envelope.salt.base64EncodedString(),
            rounds: derivationRounds,
            outputLength: 32
        )
        do {
            let box = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: envelope.nonce),
                ciphertext: envelope.ciphertext,
                tag: envelope.tag
            )
            return try AES.GCM.open(
                box,
                using: SymmetricKey(data: keyData)
            )
        } catch {
            throw SignerWalletVaultError.invalidPasscode
        }
    }
}

struct EncryptedEnvelope: Codable, Equatable, Sendable {
    let version: Int
    let salt: Data
    let nonce: Data
    let ciphertext: Data
    let tag: Data
}
