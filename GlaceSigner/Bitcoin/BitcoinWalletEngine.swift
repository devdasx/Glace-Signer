import Foundation
import P256K

enum BitcoinNetwork: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case mainnet
    case testnet

    var id: Self { self }

    var coinType: UInt32 {
        switch self {
        case .mainnet: 0
        case .testnet: 1
        }
    }

    var bech32HumanReadablePart: String {
        switch self {
        case .mainnet: "bc"
        case .testnet: "tb"
        }
    }

    var p2pkhVersion: UInt8 {
        switch self {
        case .mainnet: 0x00
        case .testnet: 0x6f
        }
    }

    var p2shVersion: UInt8 {
        switch self {
        case .mainnet: 0x05
        case .testnet: 0xc4
        }
    }
}

enum SignerImportKind: String, CaseIterable, Hashable, Identifiable, Sendable {
    case mnemonic
    case extendedPrivateKey
    case rawPrivateKey
    case walletImportFormat

    var id: Self { self }
}

enum ExtendedKeyStyle: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case legacy
    case nestedSegWit
    case nativeSegWit
    case nestedMultisig
    case nativeMultisig
    case taproot

    var id: Self { self }
}

enum BitcoinWalletEngineError: Error, Equatable {
    case invalidExtendedPrivateKey
    case ambiguousExtendedPrivateKey
    case unsupportedExtendedPrivateKey
    case invalidPrivateKey
    case invalidWalletImportFormat
    case invalidDerivation
}

struct HDPrivateKey: Codable, Equatable, Sendable {
    let privateKey: Data
    let chainCode: Data
    let depth: UInt8
    let parentFingerprint: UInt32
    let childNumber: UInt32
    let network: BitcoinNetwork
    let sourceStyle: ExtendedKeyStyle

    static func master(seed: Data, network: BitcoinNetwork) throws -> HDPrivateKey {
        let digest = BitcoinEncoding.hmacSHA512(
            key: Data("Bitcoin seed".utf8),
            data: seed
        )
        let secret = Data(digest.prefix(32))
        _ = try validatedPrivateKey(secret)
        return HDPrivateKey(
            privateKey: secret,
            chainCode: Data(digest.suffix(32)),
            depth: 0,
            parentFingerprint: 0,
            childNumber: 0,
            network: network,
            sourceStyle: .legacy
        )
    }

    static func parse(
        _ encoded: String,
        standardStyle: ExtendedKeyStyle?
    ) throws -> HDPrivateKey {
        let payload: Data
        do {
            payload = try BitcoinEncoding.base58CheckDecode(
                encoded.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } catch {
            throw BitcoinWalletEngineError.invalidExtendedPrivateKey
        }

        guard payload.count == 78,
              let version = try? BitcoinEncoding.uint32(Data(payload[0..<4])),
              let versionInfo = ExtendedKeyVersion.privateVersions[version],
              payload[45] == 0 else {
            throw BitcoinWalletEngineError.invalidExtendedPrivateKey
        }

        let depth = payload[4]
        if depth == 0, !payload[5..<13].allSatisfy({ $0 == 0 }) {
            throw BitcoinWalletEngineError.invalidExtendedPrivateKey
        }

        let resolvedStyle: ExtendedKeyStyle
        if depth > 0, versionInfo.style == .legacy {
            guard let standardStyle else {
                throw BitcoinWalletEngineError.ambiguousExtendedPrivateKey
            }
            resolvedStyle = standardStyle
        } else {
            resolvedStyle = versionInfo.style
        }

        let secret = Data(payload[46..<78])
        do {
            _ = try validatedPrivateKey(secret)
        } catch {
            throw BitcoinWalletEngineError.invalidPrivateKey
        }

        guard let parentFingerprint = try? BitcoinEncoding.uint32(Data(payload[5..<9])),
              let childNumber = try? BitcoinEncoding.uint32(Data(payload[9..<13])) else {
            throw BitcoinWalletEngineError.invalidExtendedPrivateKey
        }
        return HDPrivateKey(
            privateKey: secret,
            chainCode: Data(payload[13..<45]),
            depth: depth,
            parentFingerprint: parentFingerprint,
            childNumber: childNumber,
            network: versionInfo.network,
            sourceStyle: resolvedStyle
        )
    }

    func derived(path: [UInt32]) throws -> HDPrivateKey {
        try path.reduce(self) { key, index in
            try key.derived(at: index)
        }
    }

    func derived(at index: UInt32) throws -> HDPrivateKey {
        guard depth < UInt8.max else {
            throw BitcoinWalletEngineError.invalidDerivation
        }

        let parentKey: P256K.Signing.PrivateKey
        do {
            parentKey = try Self.validatedPrivateKey(privateKey)
        } catch {
            throw BitcoinWalletEngineError.invalidPrivateKey
        }

        var data = Data()
        if index >= 0x8000_0000 {
            data.append(0)
            data.append(privateKey)
        } else {
            data.append(parentKey.publicKey.dataRepresentation)
        }
        data.append(BitcoinEncoding.uint32Data(index))

        let digest = BitcoinEncoding.hmacSHA512(key: chainCode, data: data)
        let tweak = Data(digest.prefix(32))
        do {
            _ = try Self.validatedPrivateKey(tweak)
            let childKey = try parentKey.add(Array(tweak))
            return HDPrivateKey(
                privateKey: childKey.dataRepresentation,
                chainCode: Data(digest.suffix(32)),
                depth: depth + 1,
                parentFingerprint: try fingerprint(),
                childNumber: index,
                network: network,
                sourceStyle: sourceStyle
            )
        } catch {
            throw BitcoinWalletEngineError.invalidDerivation
        }
    }

    func serializedPublicKey(style: ExtendedKeyStyle) throws -> String {
        let privateKey = try Self.validatedPrivateKey(privateKey)
        var payload = Data()
        payload.append(
            BitcoinEncoding.uint32Data(
                ExtendedKeyVersion.publicVersion(network: network, style: style)
            )
        )
        payload.append(depth)
        payload.append(BitcoinEncoding.uint32Data(parentFingerprint))
        payload.append(BitcoinEncoding.uint32Data(childNumber))
        payload.append(chainCode)
        payload.append(privateKey.publicKey.dataRepresentation)
        return BitcoinEncoding.base58CheckEncode(payload)
    }

    func publicKey() throws -> Data {
        try Self.validatedPrivateKey(privateKey).publicKey.dataRepresentation
    }

    private func fingerprint() throws -> UInt32 {
        let hash = BitcoinEncoding.hash160(try publicKey())
        return try BitcoinEncoding.uint32(Data(hash.prefix(4)))
    }

    private static func validatedPrivateKey(
        _ data: Data
    ) throws -> P256K.Signing.PrivateKey {
        try P256K.Signing.PrivateKey(
            dataRepresentation: data,
            format: .compressed
        )
    }
}

struct SinglePrivateKey: Codable, Equatable, Sendable {
    let data: Data
    let network: BitcoinNetwork
    let isCompressed: Bool

    static func rawHex(_ value: String, network: BitcoinNetwork) throws -> SinglePrivateKey {
        let data: Data
        do {
            data = try BitcoinEncoding.hexData(value)
            _ = try P256K.Signing.PrivateKey(
                dataRepresentation: data,
                format: .compressed
            )
        } catch {
            throw BitcoinWalletEngineError.invalidPrivateKey
        }
        return SinglePrivateKey(data: data, network: network, isCompressed: true)
    }

    static func walletImportFormat(_ value: String) throws -> SinglePrivateKey {
        let payload: Data
        do {
            payload = try BitcoinEncoding.base58CheckDecode(
                value.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } catch {
            throw BitcoinWalletEngineError.invalidWalletImportFormat
        }

        guard payload.count == 33 || payload.count == 34 else {
            throw BitcoinWalletEngineError.invalidWalletImportFormat
        }
        let network: BitcoinNetwork
        switch payload[0] {
        case 0x80: network = .mainnet
        case 0xef: network = .testnet
        default: throw BitcoinWalletEngineError.invalidWalletImportFormat
        }
        let isCompressed = payload.count == 34
        if isCompressed, payload.last != 0x01 {
            throw BitcoinWalletEngineError.invalidWalletImportFormat
        }
        let keyData = Data(payload[1..<33])
        do {
            _ = try P256K.Signing.PrivateKey(
                dataRepresentation: keyData,
                format: isCompressed ? .compressed : .uncompressed
            )
        } catch {
            throw BitcoinWalletEngineError.invalidPrivateKey
        }
        return SinglePrivateKey(
            data: keyData,
            network: network,
            isCompressed: isCompressed
        )
    }

    func publicKey() throws -> Data {
        try P256K.Signing.PrivateKey(
            dataRepresentation: data,
            format: isCompressed ? .compressed : .uncompressed
        )
        .publicKey
        .dataRepresentation
    }
}

enum SignerSecretSource: Codable, Equatable, Sendable {
    case mnemonic(BIP39Mnemonic, passphrase: String, network: BitcoinNetwork)
    case extendedPrivateKey(HDPrivateKey)
    case singlePrivateKey(SinglePrivateKey)
}

struct SignerPublicAccount: Equatable, Identifiable, Sendable {
    let style: ExtendedKeyStyle
    let derivationPath: String
    let extendedPublicKey: String

    var id: ExtendedKeyStyle { style }
}

struct SignerPublicValue: Equatable, Identifiable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case publicKey
        case legacyAddress
        case nestedSegWitAddress
        case nativeSegWitAddress
        case taprootAddress
    }

    let kind: Kind
    let value: String

    var id: Kind { kind }
}

struct SignerWalletData: Equatable, Sendable {
    let network: BitcoinNetwork
    let accounts: [SignerPublicAccount]
    let singleKeyValues: [SignerPublicValue]
    let recoveryPhrase: String?

    var isHierarchical: Bool {
        !accounts.isEmpty
    }
}

enum BitcoinWalletEngine {
    static func importMnemonic(
        _ phrase: String,
        passphrase: String,
        network: BitcoinNetwork
    ) throws -> SignerSecretSource {
        .mnemonic(
            try BIP39.validate(phrase),
            passphrase: passphrase,
            network: network
        )
    }

    static func importExtendedPrivateKey(
        _ value: String,
        standardStyle: ExtendedKeyStyle?
    ) throws -> SignerSecretSource {
        .extendedPrivateKey(
            try HDPrivateKey.parse(value, standardStyle: standardStyle)
        )
    }

    static func importRawPrivateKey(
        _ value: String,
        network: BitcoinNetwork
    ) throws -> SignerSecretSource {
        .singlePrivateKey(try SinglePrivateKey.rawHex(value, network: network))
    }

    static func importWalletImportFormat(_ value: String) throws -> SignerSecretSource {
        .singlePrivateKey(try SinglePrivateKey.walletImportFormat(value))
    }

    static func createWallet(network: BitcoinNetwork) throws -> (SignerSecretSource, SignerWalletData) {
        let mnemonic = try BIP39.generate(wordCount: 24)
        let source = SignerSecretSource.mnemonic(
            mnemonic,
            passphrase: "",
            network: network
        )
        return (source, try publicData(for: source, revealsRecoveryPhrase: true))
    }

    static func publicData(
        for source: SignerSecretSource,
        revealsRecoveryPhrase: Bool
    ) throws -> SignerWalletData {
        switch source {
        case let .mnemonic(mnemonic, passphrase, network):
            let seed = try BIP39.seed(from: mnemonic, passphrase: passphrase)
            let master = try HDPrivateKey.master(seed: seed, network: network)
            return SignerWalletData(
                network: network,
                accounts: try accountPublicKeys(master: master),
                singleKeyValues: [],
                recoveryPhrase: revealsRecoveryPhrase ? mnemonic.phrase : nil
            )

        case let .extendedPrivateKey(key):
            let accounts: [SignerPublicAccount]
            if key.depth == 0 {
                accounts = try accountPublicKeys(master: key)
            } else {
                accounts = [
                    SignerPublicAccount(
                        style: key.sourceStyle,
                        derivationPath: "",
                        extendedPublicKey: try key.serializedPublicKey(style: key.sourceStyle)
                    )
                ]
            }
            return SignerWalletData(
                network: key.network,
                accounts: accounts,
                singleKeyValues: [],
                recoveryPhrase: nil
            )

        case let .singlePrivateKey(key):
            return SignerWalletData(
                network: key.network,
                accounts: [],
                singleKeyValues: try publicValues(for: key),
                recoveryPhrase: nil
            )
        }
    }

    private static func accountPublicKeys(
        master: HDPrivateKey
    ) throws -> [SignerPublicAccount] {
        let hardened: UInt32 = 0x8000_0000
        let coin = master.network.coinType | hardened
        let account = UInt32(0) | hardened
        let definitions: [(UInt32, ExtendedKeyStyle, String)] = [
            (44, .legacy, "m/44'/\(master.network.coinType)'/0'"),
            (49, .nestedSegWit, "m/49'/\(master.network.coinType)'/0'"),
            (84, .nativeSegWit, "m/84'/\(master.network.coinType)'/0'"),
            (86, .taproot, "m/86'/\(master.network.coinType)'/0'")
        ]

        return try definitions.map { purpose, style, path in
            let key = try master.derived(
                path: [purpose | hardened, coin, account]
            )
            return SignerPublicAccount(
                style: style,
                derivationPath: path,
                extendedPublicKey: try key.serializedPublicKey(style: style)
            )
        }
    }

    private static func publicValues(
        for key: SinglePrivateKey
    ) throws -> [SignerPublicValue] {
        let publicKey = try key.publicKey()
        let publicKeyHash = BitcoinEncoding.hash160(publicKey)
        var values = [
            SignerPublicValue(
                kind: .publicKey,
                value: BitcoinEncoding.hexString(publicKey)
            ),
            SignerPublicValue(
                kind: .legacyAddress,
                value: BitcoinEncoding.base58CheckEncode(
                    Data([key.network.p2pkhVersion]) + publicKeyHash
                )
            )
        ]

        guard key.isCompressed else {
            return values
        }

        let redeemScript = Data([0x00, 0x14]) + publicKeyHash
        values.append(
            SignerPublicValue(
                kind: .nestedSegWitAddress,
                value: BitcoinEncoding.base58CheckEncode(
                    Data([key.network.p2shVersion])
                        + BitcoinEncoding.hash160(redeemScript)
                )
            )
        )
        values.append(
            SignerPublicValue(
                kind: .nativeSegWitAddress,
                value: try BitcoinEncoding.encodeSegWitAddress(
                    humanReadablePart: key.network.bech32HumanReadablePart,
                    witnessVersion: 0,
                    witnessProgram: publicKeyHash
                )
            )
        )

        let signingKey = try P256K.Signing.PrivateKey(
            dataRepresentation: key.data,
            format: .compressed
        )
        let internalKey = signingKey.publicKey.xonly
        let tagHash = BitcoinEncoding.sha256(Data("TapTweak".utf8))
        let tweak = BitcoinEncoding.sha256(
            tagHash + tagHash + Data(internalKey.bytes)
        )
        let schnorrKey = P256K.Schnorr.XonlyKey(
            dataRepresentation: internalKey.bytes,
            keyParity: internalKey.parity ? 1 : 0
        )
        let outputKey = try schnorrKey.add(Array(tweak))
        values.append(
            SignerPublicValue(
                kind: .taprootAddress,
                value: try BitcoinEncoding.encodeSegWitAddress(
                    humanReadablePart: key.network.bech32HumanReadablePart,
                    witnessVersion: 1,
                    witnessProgram: Data(outputKey.bytes)
                )
            )
        )
        return values
    }
}

private enum ExtendedKeyVersion {
    struct Info {
        let network: BitcoinNetwork
        let style: ExtendedKeyStyle
    }

    static let privateVersions: [UInt32: Info] = [
        0x0488_ade4: Info(network: .mainnet, style: .legacy),
        0x049d_7878: Info(network: .mainnet, style: .nestedSegWit),
        0x04b2_430c: Info(network: .mainnet, style: .nativeSegWit),
        0x0295_b005: Info(network: .mainnet, style: .nestedMultisig),
        0x02aa_7a99: Info(network: .mainnet, style: .nativeMultisig),
        0x0435_8394: Info(network: .testnet, style: .legacy),
        0x044a_4e28: Info(network: .testnet, style: .nestedSegWit),
        0x045f_18bc: Info(network: .testnet, style: .nativeSegWit),
        0x0242_85b5: Info(network: .testnet, style: .nestedMultisig),
        0x0257_5048: Info(network: .testnet, style: .nativeMultisig)
    ]

    static func publicVersion(
        network: BitcoinNetwork,
        style: ExtendedKeyStyle
    ) -> UInt32 {
        switch (network, style) {
        case (.mainnet, .legacy), (.mainnet, .taproot): 0x0488_b21e
        case (.mainnet, .nestedSegWit): 0x049d_7cb2
        case (.mainnet, .nativeSegWit): 0x04b2_4746
        case (.mainnet, .nestedMultisig): 0x0295_b43f
        case (.mainnet, .nativeMultisig): 0x02aa_7ed3
        case (.testnet, .legacy), (.testnet, .taproot): 0x0435_87cf
        case (.testnet, .nestedSegWit): 0x044a_5262
        case (.testnet, .nativeSegWit): 0x045f_1cf6
        case (.testnet, .nestedMultisig): 0x0242_89ef
        case (.testnet, .nativeMultisig): 0x0257_5483
        }
    }
}
