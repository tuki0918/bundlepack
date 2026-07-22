import CommonCrypto
import CryptoKit
import Foundation
import Security

extension BundlePackEncryptedContainer {
    struct Header {
        let iterations: UInt32
        let chunkSize: UInt32
        let chunkCount: UInt32
        let plaintextSize: UInt64
        let iconSize: UInt32
        let salt: Data
        let noncePrefix: Data
        let iconHash: Data

        func encoded() -> Data {
            var data = Data()
            data.append(BundlePackEncryptedContainer.magic)
            data.appendLittleEndian(BundlePackEncryptedContainer.version)
            data.appendLittleEndian(BundlePackEncryptedContainer.flags)
            data.appendLittleEndian(iterations)
            data.appendLittleEndian(chunkSize)
            data.appendLittleEndian(chunkCount)
            data.appendLittleEndian(plaintextSize)
            data.appendLittleEndian(iconSize)
            data.append(salt)
            data.append(noncePrefix)
            data.append(iconHash)
            return data
        }
    }

    struct ParsedHeader {
        let header: Header
        let headerData: Data
        let iconData: Data
        let fileSize: UInt64
    }

    static func parseHeader(from url: URL) throws -> ParsedHeader {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let fileSize = UInt64(values.fileSize ?? 0)
        guard fileSize >= UInt64(fixedHeaderSize) else {
            throw BundlePackEncryptionError.invalidContainer
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let headerData = try handle.read(upToCount: fixedHeaderSize),
              headerData.count == fixedHeaderSize,
              headerData.prefix(magic.count) == magic else {
            throw BundlePackEncryptionError.invalidContainer
        }

        let parsedVersion = headerData.uint16LE(at: 8)
        guard parsedVersion == version else { throw BundlePackEncryptionError.unsupportedVersion }
        guard headerData.uint16LE(at: 10) == flags else {
            throw BundlePackEncryptionError.unsupportedVersion
        }

        let parsedIterations = headerData.uint32LE(at: 12)
        let parsedChunkSize = headerData.uint32LE(at: 16)
        let parsedChunkCount = headerData.uint32LE(at: 20)
        let plaintextSize = headerData.uint64LE(at: 24)
        let iconSize = headerData.uint32LE(at: 32)
        let salt = headerData.subdata(in: 36..<52)
        let noncePrefix = headerData.subdata(in: 52..<60)
        let iconHash = headerData.subdata(in: 60..<92)

        guard parsedIterations >= 100_000,
              parsedIterations <= 5_000_000,
              parsedChunkSize >= 64 * 1_024,
              parsedChunkSize <= 16 * 1_024 * 1_024,
              plaintextSize > 0,
              plaintextSize <= maximumPlaintextSize,
              iconSize > 0,
              iconSize <= maximumIconSize else {
            throw BundlePackEncryptionError.invalidContainer
        }

        let expectedChunkCount = (plaintextSize + UInt64(parsedChunkSize) - 1) / UInt64(parsedChunkSize)
        guard expectedChunkCount == UInt64(parsedChunkCount) else {
            throw BundlePackEncryptionError.invalidContainer
        }

        let expectedFileSize = UInt64(fixedHeaderSize)
            + UInt64(iconSize)
            + plaintextSize
            + UInt64(parsedChunkCount) * authenticationTagSize
        guard fileSize == expectedFileSize else {
            throw BundlePackEncryptionError.invalidContainer
        }

        guard let iconData = try handle.read(upToCount: Int(iconSize)),
              iconData.count == Int(iconSize),
              Data(SHA256.hash(data: iconData)) == iconHash,
              BundlePackIconValidator.isValidPNG(iconData) else {
            throw BundlePackEncryptionError.invalidIcon
        }

        return ParsedHeader(
            header: Header(
                iterations: parsedIterations,
                chunkSize: parsedChunkSize,
                chunkCount: parsedChunkCount,
                plaintextSize: plaintextSize,
                iconSize: iconSize,
                salt: salt,
                noncePrefix: noncePrefix,
                iconHash: iconHash
            ),
            headerData: headerData,
            iconData: iconData,
            fileSize: fileSize
        )
    }

    static func deriveKey(password: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        let normalized = normalizedPassword(password)
        guard normalized.count >= minimumPasswordCharacters else {
            throw BundlePackEncryptionError.passwordTooShort
        }

        var keyBytes = [UInt8](repeating: 0, count: 32)
        let status: Int32 = normalized.withCString { passwordPointer in
            salt.withUnsafeBytes { saltBuffer in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordPointer,
                    normalized.lengthOfBytes(using: .utf8),
                    saltBuffer.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    iterations,
                    &keyBytes,
                    keyBytes.count
                )
            }
        }
        guard status == kCCSuccess else { throw BundlePackEncryptionError.keyDerivationFailed }
        defer { keyBytes.resetBytes(in: 0..<keyBytes.count) }
        return SymmetricKey(data: keyBytes)
    }

    static func normalizedPassword(_ password: String) -> String {
        password.precomposedStringWithCanonicalMapping
    }

    static func randomData(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw BundlePackEncryptionError.randomGenerationFailed
        }
        return Data(bytes)
    }

    static func makeNonce(prefix: Data, index: UInt32) throws -> AES.GCM.Nonce {
        var data = prefix
        data.appendLittleEndian(index)
        return try AES.GCM.Nonce(data: data)
    }

    static func authenticatedData(headerData: Data, chunkIndex: UInt32) -> Data {
        var data = headerData
        data.appendLittleEndian(chunkIndex)
        return data
    }

    static func plaintextLength(for index: UInt32, header: Header) -> Int {
        let consumed = UInt64(index) * UInt64(header.chunkSize)
        return Int(min(UInt64(header.chunkSize), header.plaintextSize - consumed))
    }
}
private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    func uint16LE(at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func uint32LE(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }

    func uint64LE(at offset: Int) -> UInt64 {
        guard offset >= 0, offset + 8 <= count else { return 0 }
        var result: UInt64 = 0
        for index in 0..<8 {
            result |= UInt64(self[offset + index]) << UInt64(index * 8)
        }
        return result
    }
}
