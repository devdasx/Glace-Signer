import Foundation

enum DiceEntropyError: Error, Equatable {
    case invalidRoll
    case insufficientEntropy
}

struct DiceEntropyProgress: Equatable, Sendable {
    let recordedRollCount: Int
    let entropyBitCount: Int
    let acceptedPairCount: Int
    let rejectedPairCount: Int
    let entropy: Data?

    var isComplete: Bool {
        entropy != nil
    }
}

enum DiceEntropy {
    static let requiredEntropyBitCount = 256

    /// Converts independent, fair six-sided die rolls into exactly uniform
    /// entropy without using modulo reduction.
    ///
    /// Two rolls select one of 36 equally likely values. Values 0...31 emit
    /// their five-bit representation; values 32...35 are rejected. Repeating
    /// this process and taking the first 256 accepted bits produces a uniform
    /// 256-bit value suitable as BIP39 entropy for a 24-word mnemonic.
    static func progress(for rolls: [UInt8]) throws -> DiceEntropyProgress {
        guard rolls.allSatisfy({ (1...6).contains($0) }) else {
            throw DiceEntropyError.invalidRoll
        }

        var bits = [UInt8]()
        bits.reserveCapacity(requiredEntropyBitCount)
        var acceptedPairCount = 0
        var rejectedPairCount = 0

        for pairStart in stride(from: 0, to: rolls.count - 1, by: 2) {
            let first = Int(rolls[pairStart] - 1)
            let second = Int(rolls[pairStart + 1] - 1)
            let pairValue = first * 6 + second

            guard pairValue < 32 else {
                rejectedPairCount += 1
                continue
            }

            acceptedPairCount += 1
            for shift in stride(from: 4, through: 0, by: -1) {
                guard bits.count < requiredEntropyBitCount else {
                    break
                }
                bits.append(UInt8((pairValue >> shift) & 1))
            }

            if bits.count == requiredEntropyBitCount {
                break
            }
        }

        let entropy = bits.count == requiredEntropyBitCount
            ? data(from: bits)
            : nil
        return DiceEntropyProgress(
            recordedRollCount: rolls.count,
            entropyBitCount: bits.count,
            acceptedPairCount: acceptedPairCount,
            rejectedPairCount: rejectedPairCount,
            entropy: entropy
        )
    }

    static func entropy(from rolls: [UInt8]) throws -> Data {
        guard let entropy = try progress(for: rolls).entropy else {
            throw DiceEntropyError.insufficientEntropy
        }
        return entropy
    }

    private static func data(from bits: [UInt8]) -> Data {
        var result = Data()
        result.reserveCapacity(requiredEntropyBitCount / 8)

        for byteStart in stride(
            from: 0,
            to: requiredEntropyBitCount,
            by: 8
        ) {
            let byte = bits[byteStart..<(byteStart + 8)].reduce(UInt8(0)) {
                ($0 << 1) | $1
            }
            result.append(byte)
        }
        return result
    }
}
