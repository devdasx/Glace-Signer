import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import GlaceSignerCore
#else
@testable import GlaceSigner
#endif

struct DiceEntropyTests {
    @Test
    func acceptedDicePairsMatchPublished24WordBIP39Vectors() throws {
        let zeroRolls = repeatedPair([1, 1], count: 52)
        let zeroProgress = try DiceEntropy.progress(for: zeroRolls)

        #expect(zeroProgress.entropyBitCount == 256)
        #expect(zeroProgress.acceptedPairCount == 52)
        #expect(zeroProgress.rejectedPairCount == 0)
        #expect(zeroProgress.entropy == Data(repeating: 0, count: 32))
        #expect(
            try BIP39.mnemonic(from: #require(zeroProgress.entropy)).phrase
                == "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art"
        )

        let oneRolls = repeatedPair([6, 2], count: 52)
        let oneProgress = try DiceEntropy.progress(for: oneRolls)

        #expect(oneProgress.entropy == Data(repeating: 0xff, count: 32))
        #expect(
            try BIP39.mnemonic(from: #require(oneProgress.entropy)).phrase
                == "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo vote"
        )

        var acceptedOutputs = Set<Data>()
        for pairValue in 0..<32 {
            let pair: [UInt8] = [
                UInt8(pairValue / 6 + 1),
                UInt8(pairValue % 6 + 1)
            ]
            acceptedOutputs.insert(
                try DiceEntropy.entropy(
                    from: repeatedPair(pair, count: 52)
                )
            )
        }
        #expect(acceptedOutputs.count == 32)
    }

    @Test
    func rejectsFourPairValuesWithoutChangingTheEntropy() throws {
        let rejectedPairs: [[UInt8]] = [
            [6, 3],
            [6, 4],
            [6, 5],
            [6, 6]
        ]

        for rejectedPair in rejectedPairs {
            let rolls = rejectedPair + repeatedPair([1, 1], count: 52)
            let progress = try DiceEntropy.progress(for: rolls)

            #expect(progress.recordedRollCount == 106)
            #expect(progress.acceptedPairCount == 52)
            #expect(progress.rejectedPairCount == 1)
            #expect(progress.entropy == Data(repeating: 0, count: 32))
        }
    }

    @Test
    func requiresCompleteValidPhysicalDieInput() throws {
        let incomplete = repeatedPair([1, 1], count: 51)
        let progress = try DiceEntropy.progress(for: incomplete)

        #expect(progress.entropyBitCount == 255)
        #expect(progress.entropy == nil)
        #expect(throws: DiceEntropyError.insufficientEntropy) {
            _ = try DiceEntropy.entropy(from: incomplete)
        }
        #expect(throws: DiceEntropyError.invalidRoll) {
            _ = try DiceEntropy.progress(for: [0, 1])
        }
        #expect(throws: DiceEntropyError.invalidRoll) {
            _ = try DiceEntropy.progress(for: [7, 1])
        }
    }

    private func repeatedPair(
        _ pair: [UInt8],
        count: Int
    ) -> [UInt8] {
        Array(repeating: pair, count: count).flatMap { $0 }
    }
}
