import CommonCrypto
import CryptoKit
import Foundation
import Security

struct EncryptedBundlePackInfo: Sendable {
    let url: URL
    let iconData: Data
    let encryptedSize: UInt64
    let originalArchiveSize: UInt64
}

enum BundlePackEncryptionError: LocalizedError {
    case passwordTooShort
    case invalidContainer
    case unsupportedVersion
    case invalidIcon
    case randomGenerationFailed
    case keyDerivationFailed
    case wrongPasswordOrTampered
    case containerTooLarge
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .passwordTooShort:
            return "The password must contain at least 12 characters."
        case .invalidContainer:
            return "The file is not an encrypted BundlePack or is damaged."
        case .unsupportedVersion:
            return "This encrypted BundlePack version is not supported."
        case .invalidIcon:
            return "The public package icon is invalid."
        case .randomGenerationFailed:
            return "Secure random data could not be generated."
        case .keyDerivationFailed:
            return "The encryption key could not be derived."
        case .wrongPasswordOrTampered:
            return "The password is incorrect, or the package has been modified or damaged."
        case .containerTooLarge:
            return "The encrypted package exceeds the safety limit."
        case .writeFailed:
            return "The encrypted package could not be written."
        }
    }
}

enum BundlePackEncryptedContainer {
    private static let magic = Data("BPKENC01".utf8)
    private static let version: UInt16 = 1
    private static let flags: UInt16 = 1
    private static let iterations: UInt32 = 600_000
    private static let chunkSize: UInt32 = 4 * 1_024 * 1_024
    private static let fixedHeaderSize = 92
    private static let saltSize = 16
    private static let noncePrefixSize = 8
    private static let iconHashSize = 32
    private static let authenticationTagSize: UInt64 = 16
    private static let maximumIconSize: UInt32 = 16 * 1_024 * 1_024
    private static let maximumPlaintextSize: UInt64 = 20 * 1_024 * 1_024 * 1_024

    static func isEncrypted(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: magic.count)) == magic
    }

    static func readPublicInfo(from url: URL) throws -> EncryptedBundlePackInfo {
        let parsed = try parseHeader(from: url)
        return EncryptedBundlePackInfo(
            url: url,
            iconData: parsed.iconData,
            encryptedSize: parsed.fileSize,
            originalArchiveSize: parsed.header.plaintextSize
        )
    }

    static func seal(
        archive archiveURL: URL,
        iconData: Data,
        password: String,
        to destinationURL: URL
    ) throws -> EncryptedBundlePackInfo {
        guard normalizedPassword(password).count >= 12 else {
            throw BundlePackEncryptionError.passwordTooShort
        }
        guard !iconData.isEmpty, iconData.count <= Int(maximumIconSize) else {
            throw BundlePackEncryptionError.invalidIcon
        }

        let values = try archiveURL.resourceValues(forKeys: [.fileSizeKey])
        let plaintextSize = UInt64(values.fileSize ?? 0)
        guard plaintextSize > 0, plaintextSize <= maximumPlaintextSize else {
            throw BundlePackEncryptionError.containerTooLarge
        }

        let chunkCount64 = (plaintextSize + UInt64(chunkSize) - 1) / UInt64(chunkSize)
        guard chunkCount64 <= UInt64(UInt32.max) else {
            throw BundlePackEncryptionError.containerTooLarge
        }

        let salt = try randomData(count: saltSize)
        let noncePrefix = try randomData(count: noncePrefixSize)
        let iconHash = Data(SHA256.hash(data: iconData))
        let header = Header(
            iterations: iterations,
            chunkSize: chunkSize,
            chunkCount: UInt32(chunkCount64),
            plaintextSize: plaintextSize,
            iconSize: UInt32(iconData.count),
            salt: salt,
            noncePrefix: noncePrefix,
            iconHash: iconHash
        )
        let headerData = header.encoded()
        let key = try deriveKey(password: password, salt: salt, iterations: iterations)

        let fileManager = FileManager.default
        let temporaryURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp")
        fileManager.createFile(atPath: temporaryURL.path, contents: nil)
        defer { try? fileManager.removeItem(at: temporaryURL) }

        let input = try FileHandle(forReadingFrom: archiveURL)
        let output = try FileHandle(forWritingTo: temporaryURL)
        defer {
            try? input.close()
            try? output.close()
        }

        do {
            try output.write(contentsOf: headerData)
            try output.write(contentsOf: iconData)

            for index in 0..<header.chunkCount {
                let expected = plaintextLength(for: index, header: header)
                guard let plaintext = try input.read(upToCount: expected), plaintext.count == expected else {
                    throw BundlePackEncryptionError.invalidContainer
                }
                let nonce = try makeNonce(prefix: noncePrefix, index: index)
                let aad = authenticatedData(headerData: headerData, chunkIndex: index)
                let sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: aad)
                try output.write(contentsOf: sealed.ciphertext)
                try output.write(contentsOf: sealed.tag)
            }
            try output.synchronize()
            try output.close()
            try input.close()

            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        } catch let error as BundlePackEncryptionError {
            throw error
        } catch {
            throw BundlePackEncryptionError.writeFailed
        }

        return try readPublicInfo(from: destinationURL)
    }

    static func open(
        _ encryptedURL: URL,
        password: String,
        to archiveURL: URL
    ) throws {
        let parsed = try parseHeader(from: encryptedURL)
        let header = parsed.header
        let key = try deriveKey(password: password, salt: header.salt, iterations: header.iterations)
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: archiveURL.path) {
            try fileManager.removeItem(at: archiveURL)
        }
        fileManager.createFile(atPath: archiveURL.path, contents: nil)

        let input = try FileHandle(forReadingFrom: encryptedURL)
        let output = try FileHandle(forWritingTo: archiveURL)
        var completed = false
        defer {
            try? input.close()
            try? output.close()
            if !completed { try? fileManager.removeItem(at: archiveURL) }
        }

        try input.seek(toOffset: UInt64(fixedHeaderSize) + UInt64(header.iconSize))
        do {
            for index in 0..<header.chunkCount {
                let plaintextLength = plaintextLength(for: index, header: header)
                guard let ciphertext = try input.read(upToCount: plaintextLength),
                      ciphertext.count == plaintextLength,
                      let tag = try input.read(upToCount: Int(authenticationTagSize)),
                      tag.count == Int(authenticationTagSize) else {
                    throw BundlePackEncryptionError.invalidContainer
                }

                let nonce = try makeNonce(prefix: header.noncePrefix, index: index)
                let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
                let aad = authenticatedData(headerData: parsed.headerData, chunkIndex: index)
                let plaintext = try AES.GCM.open(sealedBox, using: key, authenticating: aad)
                try output.write(contentsOf: plaintext)
            }
            try output.synchronize()
            completed = true
        } catch let error as BundlePackEncryptionError {
            throw error
        } catch {
            throw BundlePackEncryptionError.wrongPasswordOrTampered
        }
    }

    private struct Header {
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

    private struct ParsedHeader {
        let header: Header
        let headerData: Data
        let iconData: Data
        let fileSize: UInt64
    }

    private static func parseHeader(from url: URL) throws -> ParsedHeader {
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
              Data(SHA256.hash(data: iconData)) == iconHash else {
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

    private static func deriveKey(password: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        let normalized = normalizedPassword(password)
        guard normalized.count >= 12 else { throw BundlePackEncryptionError.passwordTooShort }

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

    private static func normalizedPassword(_ password: String) -> String {
        password.precomposedStringWithCanonicalMapping
    }

    private static func randomData(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw BundlePackEncryptionError.randomGenerationFailed
        }
        return Data(bytes)
    }

    private static func makeNonce(prefix: Data, index: UInt32) throws -> AES.GCM.Nonce {
        var data = prefix
        data.appendLittleEndian(index)
        return try AES.GCM.Nonce(data: data)
    }

    private static func authenticatedData(headerData: Data, chunkIndex: UInt32) -> Data {
        var data = headerData
        data.appendLittleEndian(chunkIndex)
        return data
    }

    private static func plaintextLength(for index: UInt32, header: Header) -> Int {
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
