import CryptoKit
import Foundation

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
            return "The password must contain at least \(BundlePackEncryptedContainer.minimumPasswordCharacters) characters."
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
    static let minimumPasswordCharacters = 12
    static let magic = Data("BPKENC01".utf8)
    static let version: UInt16 = 1
    static let flags: UInt16 = 1
    static let iterations: UInt32 = 600_000
    static let chunkSize: UInt32 = 4 * 1_024 * 1_024
    static let fixedHeaderSize = 92
    static let saltSize = 16
    static let noncePrefixSize = 8
    static let authenticationTagSize: UInt64 = 16
    static let maximumIconSize: UInt32 = 16 * 1_024 * 1_024
    static let maximumPlaintextSize: UInt64 = 20 * 1_024 * 1_024 * 1_024

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
        to destinationURL: URL,
        progress: BundlePackProgressHandler? = nil
    ) throws -> EncryptedBundlePackInfo {
        try Task.checkCancellation()
        guard normalizedPassword(password).count >= minimumPasswordCharacters else {
            throw BundlePackEncryptionError.passwordTooShort
        }
        guard !iconData.isEmpty,
              iconData.count <= Int(maximumIconSize),
              BundlePackIconValidator.isValidPNG(iconData) else {
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
            progress?(BundlePackOperationProgress(
                fractionCompleted: 0,
                message: "Encrypting package…"
            ))

            for index in 0..<header.chunkCount {
                try Task.checkCancellation()
                let expected = plaintextLength(for: index, header: header)
                guard let plaintext = try input.read(upToCount: expected), plaintext.count == expected else {
                    throw BundlePackEncryptionError.invalidContainer
                }
                let nonce = try makeNonce(prefix: noncePrefix, index: index)
                let aad = authenticatedData(headerData: headerData, chunkIndex: index)
                let sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: aad)
                try output.write(contentsOf: sealed.ciphertext)
                try output.write(contentsOf: sealed.tag)
                progress?(BundlePackOperationProgress(
                    fractionCompleted: Double(index + 1) / Double(header.chunkCount),
                    message: "Encrypting package…"
                ))
            }
            try output.synchronize()
            try output.close()
            try input.close()

            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        } catch is CancellationError {
            throw CancellationError()
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
        to archiveURL: URL,
        progress: BundlePackProgressHandler? = nil
    ) throws {
        try Task.checkCancellation()
        let parsed = try parseHeader(from: encryptedURL)
        let header = parsed.header
        let key = try deriveKey(password: password, salt: header.salt, iterations: header.iterations)
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: archiveURL.path) {
            try fileManager.removeItem(at: archiveURL)
        }
        guard fileManager.createFile(atPath: archiveURL.path, contents: nil) else {
            throw BundlePackEncryptionError.writeFailed
        }
        do {
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: archiveURL.path)
        } catch {
            try? fileManager.removeItem(at: archiveURL)
            throw BundlePackEncryptionError.writeFailed
        }

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
            progress?(BundlePackOperationProgress(
                fractionCompleted: 0,
                message: "Decrypting package…"
            ))
            for index in 0..<header.chunkCount {
                try Task.checkCancellation()
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
                progress?(BundlePackOperationProgress(
                    fractionCompleted: Double(index + 1) / Double(header.chunkCount),
                    message: "Decrypting package…"
                ))
            }
            try output.synchronize()
            completed = true
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as BundlePackEncryptionError {
            throw error
        } catch {
            throw BundlePackEncryptionError.wrongPasswordOrTampered
        }
    }
}
