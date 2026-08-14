import Foundation

enum BIP39Error: Error, Equatable {
    case unsupportedWordCount
    case unknownWord
    case invalidChecksum
    case wordListUnavailable
}

struct BIP39Mnemonic: Codable, Equatable, Sendable {
    let words: [String]

    var phrase: String {
        words.joined(separator: " ")
    }
}

enum BIP39 {
    static let supportedWordCounts = [12, 15, 18, 21, 24]

    static func generate(wordCount: Int = 24) throws -> BIP39Mnemonic {
        guard supportedWordCounts.contains(wordCount) else {
            throw BIP39Error.unsupportedWordCount
        }

        let entropyBitCount = wordCount * 11 * 32 / 33
        let entropy = try BitcoinEncoding.randomBytes(count: entropyBitCount / 8)
        return try mnemonic(from: entropy)
    }

    static func validate(_ phrase: String) throws -> BIP39Mnemonic {
        let words = normalizedWords(phrase)
        guard supportedWordCounts.contains(words.count) else {
            throw BIP39Error.unsupportedWordCount
        }

        let wordList = try englishWordList()
        let indexes = Dictionary(
            uniqueKeysWithValues: wordList.enumerated().map { ($1, $0) }
        )
        let wordIndexes = try words.map { word -> Int in
            guard let index = indexes[word] else {
                throw BIP39Error.unknownWord
            }
            return index
        }

        let totalBitCount = words.count * 11
        let entropyBitCount = totalBitCount * 32 / 33
        let checksumBitCount = totalBitCount - entropyBitCount
        let bits = wordIndexes.flatMap { index in
            (0..<11).reversed().map { (index >> $0) & 1 }
        }
        let entropy = data(from: Array(bits.prefix(entropyBitCount)))
        let expectedChecksum = checksumBits(
            for: entropy,
            count: checksumBitCount
        )
        guard Array(bits.suffix(checksumBitCount)) == expectedChecksum else {
            throw BIP39Error.invalidChecksum
        }
        return BIP39Mnemonic(words: words)
    }

    static func seed(
        from mnemonic: BIP39Mnemonic,
        passphrase: String
    ) throws -> Data {
        let normalizedMnemonic = mnemonic.phrase.decomposedStringWithCompatibilityMapping
        let normalizedPassphrase = passphrase.decomposedStringWithCompatibilityMapping
        return try BitcoinEncoding.pbkdf2SHA512(
            password: normalizedMnemonic,
            salt: "mnemonic" + normalizedPassphrase,
            rounds: 2_048,
            outputLength: 64
        )
    }

    private static func mnemonic(from entropy: Data) throws -> BIP39Mnemonic {
        guard [16, 20, 24, 28, 32].contains(entropy.count) else {
            throw BIP39Error.unsupportedWordCount
        }

        let entropyBits = entropy.flatMap { byte in
            (0..<8).reversed().map { Int((byte >> $0) & 1) }
        }
        let checksum = checksumBits(for: entropy, count: entropy.count / 4)
        let bits = entropyBits + checksum
        let wordList = try englishWordList()

        var words = [String]()
        words.reserveCapacity(bits.count / 11)
        for start in stride(from: 0, to: bits.count, by: 11) {
            let index = bits[start..<(start + 11)].reduce(0) {
                ($0 << 1) | $1
            }
            words.append(wordList[index])
        }
        return BIP39Mnemonic(words: words)
    }

    private static func normalizedWords(_ phrase: String) -> [String] {
        phrase
            .decomposedStringWithCompatibilityMapping
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    private static func checksumBits(for entropy: Data, count: Int) -> [Int] {
        let digest = BitcoinEncoding.sha256(entropy)
        return digest.flatMap { byte in
            (0..<8).reversed().map { Int((byte >> $0) & 1) }
        }
        .prefix(count)
        .map { $0 }
    }

    private static func data(from bits: [Int]) -> Data {
        var result = Data()
        result.reserveCapacity(bits.count / 8)
        for start in stride(from: 0, to: bits.count, by: 8) {
            let byte = bits[start..<(start + 8)].reduce(UInt8(0)) {
                ($0 << 1) | UInt8($1)
            }
            result.append(byte)
        }
        return result
    }

    private static func englishWordList() throws -> [String] {
        var candidateURLs = [
            Bundle.main.url(
                forResource: "english",
                withExtension: "txt",
                subdirectory: "BIP39"
            ),
            Bundle.main.url(forResource: "english", withExtension: "txt")
        ]
#if SWIFT_PACKAGE
        candidateURLs.insert(
            Bundle.module.url(
                forResource: "english",
                withExtension: "txt",
                subdirectory: "BIP39"
            ),
            at: 0
        )
        candidateURLs.insert(
            Bundle.module.url(forResource: "english", withExtension: "txt"),
            at: 0
        )
#endif
        guard let url = candidateURLs.compactMap({ $0 }).first,
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            throw BIP39Error.wordListUnavailable
        }

        let words = content.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard words.count == 2_048 else {
            throw BIP39Error.wordListUnavailable
        }
        return words
    }
}
