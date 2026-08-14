import CommonCrypto
import CryptoKit
import Foundation
import RIPEMD160
import Security

enum BitcoinEncodingError: Error, Equatable {
    case invalidBase58Character
    case invalidChecksum
    case invalidDataLength
    case invalidHex
    case invalidBech32
    case randomGenerationFailed
    case keyDerivationFailed
}

enum BitcoinEncoding {
    private static let base58Alphabet = Array(
        "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8
    )
    private static let base58Indexes: [UInt8: Int] = Dictionary(
        uniqueKeysWithValues: base58Alphabet.enumerated().map { ($1, $0) }
    )
    private static let bech32Alphabet = Array(
        "qpzry9x8gf2tvdw0s3jn54khce6mua7l".utf8
    )
    private static let bech32Indexes: [UInt8: Int] = Dictionary(
        uniqueKeysWithValues: bech32Alphabet.enumerated().map { ($1, $0) }
    )

    static func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    static func doubleSHA256(_ data: Data) -> Data {
        sha256(sha256(data))
    }

    static func hash160(_ data: Data) -> Data {
        RIPEMD160.hash(data: sha256(data))
    }

    static func hmacSHA512(key: Data, data: Data) -> Data {
        let key = SymmetricKey(data: key)
        return Data(HMAC<SHA512>.authenticationCode(for: data, using: key))
    }

    static func pbkdf2SHA512(
        password: String,
        salt: String,
        rounds: UInt32,
        outputLength: Int
    ) throws -> Data {
        let passwordBytes = Array(password.utf8)
        let saltBytes = Array(salt.utf8)
        var output = [UInt8](repeating: 0, count: outputLength)

        let status = passwordBytes.withUnsafeBufferPointer { passwordBuffer in
            saltBytes.withUnsafeBufferPointer { saltBuffer in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBuffer.baseAddress?.withMemoryRebound(
                        to: Int8.self,
                        capacity: passwordBuffer.count,
                        { $0 }
                    ),
                    passwordBuffer.count,
                    saltBuffer.baseAddress,
                    saltBuffer.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512),
                    rounds,
                    &output,
                    output.count
                )
            }
        }

        guard status == kCCSuccess else {
            throw BitcoinEncodingError.keyDerivationFailed
        }
        return Data(output)
    }

    static func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw BitcoinEncodingError.randomGenerationFailed
        }
        return Data(bytes)
    }

    static func hexData(_ value: String) throws -> Data {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count.isMultiple(of: 2) else {
            throw BitcoinEncodingError.invalidHex
        }

        var data = Data()
        data.reserveCapacity(value.count / 2)
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<next], radix: 16) else {
                throw BitcoinEncodingError.invalidHex
            }
            data.append(byte)
            index = next
        }
        return data
    }

    static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func base58CheckEncode(_ payload: Data) -> String {
        base58Encode(payload + doubleSHA256(payload).prefix(4))
    }

    static func base58CheckDecode(_ value: String) throws -> Data {
        let decoded = try base58Decode(value)
        guard decoded.count >= 5 else {
            throw BitcoinEncodingError.invalidDataLength
        }

        let payload = decoded.dropLast(4)
        let checksum = decoded.suffix(4)
        guard checksum.elementsEqual(doubleSHA256(Data(payload)).prefix(4)) else {
            throw BitcoinEncodingError.invalidChecksum
        }
        return Data(payload)
    }

    static func base58Encode(_ data: Data) -> String {
        guard !data.isEmpty else {
            return ""
        }

        let leadingZeroCount = data.prefix { $0 == 0 }.count
        var digits = [UInt8]()

        for byte in data {
            var carry = Int(byte)
            for index in digits.indices.reversed() {
                let value = Int(digits[index]) * 256 + carry
                digits[index] = UInt8(value % 58)
                carry = value / 58
            }
            while carry > 0 {
                digits.insert(UInt8(carry % 58), at: 0)
                carry /= 58
            }
        }

        let encoded = digits.drop { $0 == 0 }.map {
            Character(UnicodeScalar(base58Alphabet[Int($0)]))
        }
        return String(repeating: "1", count: leadingZeroCount) + String(encoded)
    }

    static func base58Decode(_ value: String) throws -> Data {
        guard !value.isEmpty else {
            throw BitcoinEncodingError.invalidDataLength
        }

        let input = Array(value.utf8)
        let leadingZeroCount = input.prefix { $0 == base58Alphabet[0] }.count
        var bytes = [UInt8]()

        for character in input {
            guard let characterValue = base58Indexes[character] else {
                throw BitcoinEncodingError.invalidBase58Character
            }

            var carry = characterValue
            for index in bytes.indices.reversed() {
                let result = Int(bytes[index]) * 58 + carry
                bytes[index] = UInt8(result & 0xff)
                carry = result >> 8
            }
            while carry > 0 {
                bytes.insert(UInt8(carry & 0xff), at: 0)
                carry >>= 8
            }
        }

        return Data(repeating: 0, count: leadingZeroCount)
            + Data(bytes.drop { $0 == 0 })
    }

    static func encodeSegWitAddress(
        humanReadablePart: String,
        witnessVersion: UInt8,
        witnessProgram: Data
    ) throws -> String {
        guard witnessVersion <= 16,
              (2...40).contains(witnessProgram.count),
              witnessVersion != 0 || witnessProgram.count == 20 || witnessProgram.count == 32 else {
            throw BitcoinEncodingError.invalidBech32
        }

        let converted = try convertBits(
            Array(witnessProgram),
            from: 8,
            to: 5,
            pad: true
        )
        let values = [witnessVersion] + converted
        let constant: UInt32 = witnessVersion == 0 ? 1 : 0x2bc830a3
        let checksum = bech32Checksum(
            humanReadablePart: humanReadablePart,
            values: values,
            constant: constant
        )
        let characters = (values + checksum).map {
            Character(UnicodeScalar(bech32Alphabet[Int($0)]))
        }
        return humanReadablePart.lowercased() + "1" + String(characters)
    }

    static func decodeSegWitAddress(
        _ address: String
    ) throws -> (humanReadablePart: String, witnessVersion: UInt8, witnessProgram: Data) {
        let utf8 = Array(address.utf8)
        guard (8...90).contains(utf8.count),
              !utf8.contains(where: { $0 < 33 || $0 > 126 }) else {
            throw BitcoinEncodingError.invalidBech32
        }

        let hasLowercase = address.unicodeScalars.contains {
            CharacterSet.lowercaseLetters.contains($0)
        }
        let hasUppercase = address.unicodeScalars.contains {
            CharacterSet.uppercaseLetters.contains($0)
        }
        guard !(hasLowercase && hasUppercase) else {
            throw BitcoinEncodingError.invalidBech32
        }

        let normalized = address.lowercased()
        guard let separator = normalized.lastIndex(of: "1") else {
            throw BitcoinEncodingError.invalidBech32
        }
        let hrp = String(normalized[..<separator])
        let payloadStart = normalized.index(after: separator)
        let payloadCharacters = Array(normalized[payloadStart...].utf8)
        guard !hrp.isEmpty, payloadCharacters.count >= 7 else {
            throw BitcoinEncodingError.invalidBech32
        }

        let values = try payloadCharacters.map { character -> UInt8 in
            guard let value = bech32Indexes[character] else {
                throw BitcoinEncodingError.invalidBech32
            }
            return UInt8(value)
        }
        guard let witnessVersion = values.first, witnessVersion <= 16 else {
            throw BitcoinEncodingError.invalidBech32
        }

        let checksumValue = bech32Polymod(
            bech32HrpExpand(hrp) + values
        )
        let expectedChecksum: UInt32 = witnessVersion == 0 ? 1 : 0x2bc830a3
        guard checksumValue == expectedChecksum else {
            throw BitcoinEncodingError.invalidChecksum
        }

        let programValues = Array(values.dropFirst().dropLast(6))
        let program = Data(
            try convertBits(programValues, from: 5, to: 8, pad: false)
        )
        guard (2...40).contains(program.count),
              witnessVersion != 0 || program.count == 20 || program.count == 32 else {
            throw BitcoinEncodingError.invalidBech32
        }
        return (hrp, witnessVersion, program)
    }

    static func uint32Data(_ value: UInt32) -> Data {
        Data([
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ])
    }

    static func uint32(_ bytes: Data) throws -> UInt32 {
        guard bytes.count == 4 else {
            throw BitcoinEncodingError.invalidDataLength
        }
        return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private static func bech32Checksum(
        humanReadablePart: String,
        values: [UInt8],
        constant: UInt32
    ) -> [UInt8] {
        let polymod = bech32Polymod(
            bech32HrpExpand(humanReadablePart.lowercased())
                + values
                + Array(repeating: 0, count: 6)
        ) ^ constant
        return (0..<6).map { index in
            UInt8((polymod >> UInt32(5 * (5 - index))) & 31)
        }
    }

    private static func bech32HrpExpand(_ value: String) -> [UInt8] {
        let bytes = Array(value.utf8)
        return bytes.map { $0 >> 5 } + [0] + bytes.map { $0 & 31 }
    }

    private static func bech32Polymod(_ values: [UInt8]) -> UInt32 {
        let generators: [UInt32] = [
            0x3b6a57b2,
            0x26508e6d,
            0x1ea119fa,
            0x3d4233dd,
            0x2a1462b3
        ]
        return values.reduce(UInt32(1)) { checksum, value in
            let top = checksum >> 25
            var next = ((checksum & 0x1ffffff) << 5) ^ UInt32(value)
            for index in 0..<5 where ((top >> index) & 1) == 1 {
                next ^= generators[index]
            }
            return next
        }
    }

    private static func convertBits(
        _ data: [UInt8],
        from sourceBits: Int,
        to destinationBits: Int,
        pad: Bool
    ) throws -> [UInt8] {
        var accumulator = 0
        var bitCount = 0
        var result = [UInt8]()
        let maximumValue = (1 << destinationBits) - 1
        let maximumAccumulator = (1 << (sourceBits + destinationBits - 1)) - 1

        for value in data {
            guard (Int(value) >> sourceBits) == 0 else {
                throw BitcoinEncodingError.invalidBech32
            }
            accumulator = ((accumulator << sourceBits) | Int(value)) & maximumAccumulator
            bitCount += sourceBits
            while bitCount >= destinationBits {
                bitCount -= destinationBits
                result.append(UInt8((accumulator >> bitCount) & maximumValue))
            }
        }

        if pad {
            if bitCount > 0 {
                result.append(UInt8((accumulator << (destinationBits - bitCount)) & maximumValue))
            }
        } else if bitCount >= sourceBits
                    || ((accumulator << (destinationBits - bitCount)) & maximumValue) != 0 {
            throw BitcoinEncodingError.invalidBech32
        }
        return result
    }
}
