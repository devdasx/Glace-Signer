import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import GlaceSignerCore
#else
@testable import GlaceSigner
#endif

struct BitcoinWalletEngineTests {
    @Test
    func ripemd160PublishedVector() {
        #expect(
            BitcoinEncoding.hexString(
                BitcoinEncoding.hash160(Data())
            ) == "b472a266d0bd89c13706a4132ccfb16f7c3b9fcb"
        )
    }

    @Test
    func bip39EnglishVectorOne() throws {
        let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        let mnemonic = try BIP39.validate(phrase)
        let seed = try BIP39.seed(from: mnemonic, passphrase: "TREZOR")

        #expect(
            BitcoinEncoding.hexString(seed)
                == "c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04"
        )
    }

    @Test
    func bip32VectorOneMasterAndFirstChildren() throws {
        let seed = try BitcoinEncoding.hexData(
            "000102030405060708090a0b0c0d0e0f"
        )
        let master = try HDPrivateKey.master(seed: seed, network: .mainnet)
        #expect(
            try master.serializedPublicKey(style: .legacy)
                == "xpub661MyMwAqRbcFtXgS5sYJABqqG9YLmC4Q1Rdap9gSE8NqtwybGhePY2gZ29ESFjqJoCu1Rupje8YtGqsefD265TMg7usUDFdp6W1EGMcet8"
        )

        let firstHardened = try master.derived(at: 0x8000_0000)
        #expect(
            try firstHardened.serializedPublicKey(style: .legacy)
                == "xpub68Gmy5EdvgibQVfPdqkBBCHxA5htiqg55crXYuXoQRKfDBFA1WEjWgP6LHhwBZeNK1VTsfTFUHCdrfp1bgwQ9xv5ski8PX9rL2dZXvgGDnw"
        )

        let next = try firstHardened.derived(at: 1)
        #expect(
            try next.serializedPublicKey(style: .legacy)
                == "xpub6ASuArnXKPbfEwhqN6e3mwBcDTgzisQN1wXN9BJcM47sSikHjJf3UFHKkNAWbWMiGj7Wf5uMash7SyYq527Hqck2AxYysAA7xmALppuCkwQ"
        )
    }

    @Test
    func accountXprvRequiresExplicitWalletStandard() throws {
        let seed = try BitcoinEncoding.hexData(
            "000102030405060708090a0b0c0d0e0f"
        )
        let accountKey = try HDPrivateKey.master(
            seed: seed,
            network: .mainnet
        )
        .derived(at: 0x8000_0000)

        var payload = Data()
        payload.append(BitcoinEncoding.uint32Data(0x0488_ade4))
        payload.append(accountKey.depth)
        payload.append(BitcoinEncoding.uint32Data(accountKey.parentFingerprint))
        payload.append(BitcoinEncoding.uint32Data(accountKey.childNumber))
        payload.append(accountKey.chainCode)
        payload.append(0)
        payload.append(accountKey.privateKey)
        let xprv = BitcoinEncoding.base58CheckEncode(payload)

        #expect(throws: BitcoinWalletEngineError.self) {
            _ = try BitcoinWalletEngine.importExtendedPrivateKey(
                xprv,
                standardStyle: nil
            )
        }

        let imported = try BitcoinWalletEngine.importExtendedPrivateKey(
            xprv,
            standardStyle: .nativeSegWit
        )
        guard case let .extendedPrivateKey(key) = imported else {
            Issue.record("Expected an imported extended private key")
            return
        }
        #expect(key.sourceStyle == .nativeSegWit)
    }

    @Test
    func rejectsBadBase58Checksum() {
        #expect(throws: BitcoinEncodingError.self) {
            _ = try BitcoinEncoding.base58CheckDecode(
                "xpub661MyMwAqRbcFtXgS5sYJABqqG9YLmC4Q1Rdap9gSE8NqtwybGhePY2gZ29ESFjqJoCu1Rupje8YtGqsefD265TMg7usUDFdp6W1EGMceu8"
            )
        }
    }

    @Test
    func rejectsMnemonicWithInvalidChecksum() {
        #expect(throws: BIP39Error.self) {
            _ = try BIP39.validate(
                "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon"
            )
        }
    }

    @Test
    func privateKeyOneProducesPublishedLegacyAddress() throws {
        let key = SinglePrivateKey(
            data: Data(repeating: 0, count: 31) + Data([1]),
            network: .mainnet,
            isCompressed: true
        )
        let wallet = try BitcoinWalletEngine.publicData(
            for: .singlePrivateKey(key),
            revealsRecoveryPhrase: false
        )
        #expect(
            wallet.singleKeyValues.first(where: { $0.kind == .legacyAddress })?.value
                == "1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH"
        )
    }

    @Test
    func bip86FirstReceivingAddressMatchesPublishedVector() throws {
        let mnemonic = try BIP39.validate(
            "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        )
        let seed = try BIP39.seed(from: mnemonic, passphrase: "")
        let hardened: UInt32 = 0x8000_0000
        let receivingKey = try HDPrivateKey.master(
            seed: seed,
            network: .mainnet
        )
        .derived(
            path: [
                86 | hardened,
                0 | hardened,
                0 | hardened,
                0,
                0
            ]
        )
        let wallet = try BitcoinWalletEngine.publicData(
            for: .singlePrivateKey(
                SinglePrivateKey(
                    data: receivingKey.privateKey,
                    network: .mainnet,
                    isCompressed: true
                )
            ),
            revealsRecoveryPhrase: false
        )

        #expect(
            wallet.singleKeyValues.first(where: { $0.kind == .taprootAddress })?.value
                == "bc1p5cyxnuxmeuwuvkwfem96lqzszd02n6xdcjrs20cac6yqjjwudpxqkedrcr"
        )
    }

    @Test
    func encryptedEnvelopeRejectsWrongPasscode() throws {
        let plaintext = Data("signer wallet secret".utf8)
        let envelope = try SignerWalletVault.seal(
            plaintext,
            passcode: "123456"
        )
        #expect(
            try SignerWalletVault.open(envelope, passcode: "123456")
                == plaintext
        )
        #expect(throws: SignerWalletVaultError.self) {
            _ = try SignerWalletVault.open(envelope, passcode: "654321")
        }
    }
}
