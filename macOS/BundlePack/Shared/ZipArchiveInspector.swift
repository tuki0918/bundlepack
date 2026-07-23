import CryptoKit
import Foundation

enum BundlePackArchiveError: LocalizedError {
    case unreadable
    case notZip
    case zip64Unsupported
    case invalidEntry(String)
    case unsafeEntry(String)
    case encryptedEntry(String)
    case unsupportedCompression(String)
    case duplicateEntry(String)
    case missingMetadata(String)
    case invalidIcon
    case invalidAnimation
    case invalidManifest
    case unsupportedFormat
    case archiveTooLarge

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "The package could not be read."
        case .notZip:
            return "The file is not a BundlePack or ZIP archive."
        case .zip64Unsupported:
            return "BundlePack does not support ZIP64 packages."
        case .invalidEntry(let path):
            return "A ZIP entry is invalid: \(path)"
        case .unsafeEntry(let path):
            return "An unsafe path or symbolic link was detected: \(path)"
        case .encryptedEntry(let path):
            return "Encrypted ZIP entries are not supported: \(path)"
        case .unsupportedCompression(let path):
            return "The compression method is not supported: \(path)"
        case .duplicateEntry(let path):
            return "Multiple ZIP entries resolve to the same output path: \(path)"
        case .missingMetadata(let name):
            return "Required metadata is missing: \(name)"
        case .invalidIcon:
            return "The package icon must be a 1024 × 1024 PNG image."
        case .invalidAnimation:
            return "The package animation must be a valid animated GIF within the safety limits."
        case .invalidManifest:
            return "manifest.json is invalid or does not match the package contents."
        case .unsupportedFormat:
            return "This BundlePack version is not supported."
        case .archiveTooLarge:
            return "The expanded size or file count exceeds the safety limit."
        }
    }
}
struct ZipArchiveInspector {
    static func inspect(
        _ url: URL,
        validatePayloads: Bool = false,
        progress: BundlePackProgressHandler? = nil
    ) throws -> BundlePackArchiveInfo {
        try Task.checkCancellation()
        progress?(BundlePackOperationProgress(fractionCompleted: 0, message: "Reading package…"))
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            throw BundlePackArchiveError.unreadable
        }
        try Task.checkCancellation()

        let entries = try parseEntries(in: data)
        try validate(entries: entries, archiveSize: UInt64(data.count))
        progress?(BundlePackOperationProgress(fractionCompleted: 0.1, message: "Validating package structure…"))

        guard let manifestEntry = entries.first(where: { $0.path == "manifest.json" }) else {
            throw BundlePackArchiveError.missingMetadata("manifest.json")
        }
        guard let iconEntry = entries.first(where: { $0.path == "icon.png" }) else {
            throw BundlePackArchiveError.missingMetadata("icon.png")
        }
        let animationEntry = entries.first(where: { $0.path == BundlePackAnimationValidator.path })

        let manifestData = try storedData(for: manifestEntry, in: data)
        let iconData = try storedData(for: iconEntry, in: data)
        guard BundlePackIconValidator.isValidPNG(iconData) else {
            throw BundlePackArchiveError.invalidIcon
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(BundlePackManifest.self, from: manifestData) else {
            throw BundlePackArchiveError.invalidManifest
        }
        guard manifest.format == BundlePackManifest.formatIdentifier else {
            throw BundlePackArchiveError.unsupportedFormat
        }
        guard manifest.formatVersion == BundlePackManifest.staticFormatVersion
                || manifest.formatVersion == BundlePackManifest.animatedFormatVersion else {
            throw BundlePackArchiveError.unsupportedFormat
        }
        guard manifest.hasValidAnimationLayout(hasAnimationEntry: animationEntry != nil) else {
            throw BundlePackArchiveError.invalidManifest
        }
        guard manifest.hasValidDisplayMetadata else {
            throw BundlePackArchiveError.invalidManifest
        }

        let animationData: Data?
        if let animationEntry {
            let data = try storedData(for: animationEntry, in: data)
            guard BundlePackAnimationValidator.isValidGIF(data) else {
                throw BundlePackArchiveError.invalidAnimation
            }
            animationData = data
        } else {
            animationData = nil
        }

        let payloadFiles = entries
            .filter { $0.path.hasPrefix("payload/") && !$0.path.hasSuffix("/") }
            .map {
                BundlePackFile(
                    path: String($0.path.dropFirst("payload/".count)),
                    size: $0.uncompressedSize
                )
            }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        guard manifest.files.count == payloadFiles.count,
              Set(manifest.files) == Set(payloadFiles) else {
            throw BundlePackArchiveError.invalidManifest
        }
        if validatePayloads {
            let totalPayloadBytes = payloadFiles.reduce(UInt64(0)) { $0 + $1.size }
            var validatedBytes: UInt64 = 0
            for entry in entries where entry.path.hasPrefix("payload/") && !entry.path.hasSuffix("/") {
                try Task.checkCancellation()
                try validateEntryStream(entry, in: data) { bytes in
                    validatedBytes += bytes
                    let localFraction = totalPayloadBytes == 0
                        ? 1
                        : Double(validatedBytes) / Double(totalPayloadBytes)
                    progress?(BundlePackOperationProgress(
                        fractionCompleted: 0.1 + localFraction * 0.9,
                        message: "Validating package contents…"
                    ))
                }
            }
        }
        progress?(BundlePackOperationProgress(fractionCompleted: 1, message: "Package validated"))

        return BundlePackArchiveInfo(
            url: url,
            manifest: manifest,
            iconData: iconData,
            animationData: animationData,
            payloadFiles: payloadFiles,
            archiveSize: UInt64(data.count),
            expandedSize: entries.reduce(0) { $0 + $1.uncompressedSize },
            archiveDigest: Data(SHA256.hash(data: data))
        )
    }

    static func embeddedIcon(in url: URL) throws -> Data {
        guard let icon = try leadingStoredIcon(in: url) else {
            throw BundlePackArchiveError.invalidIcon
        }
        return icon
    }
}
