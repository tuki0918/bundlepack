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
            return "This prototype does not support ZIP64 packages larger than 4 GB."
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
        case .invalidManifest:
            return "manifest.json could not be decoded."
        case .unsupportedFormat:
            return "This BundlePack version is not supported."
        case .archiveTooLarge:
            return "The expanded size or file count exceeds the safety limit."
        }
    }
}

struct ZipArchiveInspector {
    private static let endOfCentralDirectory: UInt32 = 0x0605_4b50
    private static let centralFileHeader: UInt32 = 0x0201_4b50
    private static let localFileHeader: UInt32 = 0x0403_4b50
    private static let maximumEntries = 10_000
    private static let maximumExpandedSize: UInt64 = 20 * 1_024 * 1_024 * 1_024
    private static let maximumMetadataSize: UInt64 = 16 * 1_024 * 1_024

    static func inspect(_ url: URL) throws -> BundlePackArchiveInfo {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            throw BundlePackArchiveError.unreadable
        }

        let entries = try parseEntries(in: data)
        try validate(entries: entries, archiveSize: UInt64(data.count))

        guard let manifestEntry = entries.first(where: { $0.path == "manifest.json" }) else {
            throw BundlePackArchiveError.missingMetadata("manifest.json")
        }
        guard let iconEntry = entries.first(where: { $0.path == "icon.png" }) else {
            throw BundlePackArchiveError.missingMetadata("icon.png")
        }

        let manifestData = try storedData(for: manifestEntry, in: data)
        let iconData = try storedData(for: iconEntry, in: data)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(BundlePackManifest.self, from: manifestData) else {
            throw BundlePackArchiveError.invalidManifest
        }
        guard manifest.format == BundlePackManifest.formatIdentifier,
              manifest.formatVersion == BundlePackManifest.currentFormatVersion else {
            throw BundlePackArchiveError.unsupportedFormat
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

        return BundlePackArchiveInfo(
            url: url,
            manifest: manifest,
            iconData: iconData,
            payloadFiles: payloadFiles,
            archiveSize: UInt64(data.count),
            expandedSize: entries.reduce(0) { $0 + $1.uncompressedSize }
        )
    }

    static func embeddedIcon(in url: URL) throws -> Data {
        if let icon = try leadingStoredIcon(in: url) {
            return icon
        }
        return try inspect(url).iconData
    }

    private static func leadingStoredIcon(in url: URL) throws -> Data? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        guard let header = try handle.read(upToCount: 30),
              header.count == 30,
              header.uint32LE(at: 0) == localFileHeader else {
            return nil
        }

        let flags = header.uint16LE(at: 6)
        let compressionMethod = header.uint16LE(at: 8)
        let compressedSize = UInt64(header.uint32LE(at: 18))
        let uncompressedSize = UInt64(header.uint32LE(at: 22))
        let nameLength = Int(header.uint16LE(at: 26))
        let extraLength = Int(header.uint16LE(at: 28))

        guard flags & 0x0001 == 0,
              flags & 0x0008 == 0,
              compressionMethod == 0,
              compressedSize == uncompressedSize,
              uncompressedSize > 0,
              uncompressedSize <= maximumMetadataSize else {
            return nil
        }

        guard let nameAndExtra = try handle.read(upToCount: nameLength + extraLength),
              nameAndExtra.count == nameLength + extraLength,
              let name = String(data: nameAndExtra.prefix(nameLength), encoding: .utf8),
              name == "icon.png" else {
            return nil
        }

        guard let iconData = try handle.read(upToCount: Int(uncompressedSize)),
              iconData.count == Int(uncompressedSize) else {
            throw BundlePackArchiveError.invalidEntry("icon.png")
        }
        return iconData
    }

    private struct Entry {
        let path: String
        let flags: UInt16
        let compressionMethod: UInt16
        let compressedSize: UInt64
        let uncompressedSize: UInt64
        let localHeaderOffset: UInt64
        let externalAttributes: UInt32
    }

    private static func parseEntries(in data: Data) throws -> [Entry] {
        guard data.count >= 22 else { throw BundlePackArchiveError.notZip }

        let minimumOffset = max(0, data.count - 65_557)
        var endOffset: Int?
        for offset in stride(from: data.count - 22, through: minimumOffset, by: -1) {
            if data.uint32LE(at: offset) == endOfCentralDirectory {
                endOffset = offset
                break
            }
        }
        guard let endOffset else { throw BundlePackArchiveError.notZip }

        let entryCount = Int(data.uint16LE(at: endOffset + 10))
        let centralSize = data.uint32LE(at: endOffset + 12)
        let centralOffset = data.uint32LE(at: endOffset + 16)

        if entryCount == Int(UInt16.max) || centralSize == UInt32.max || centralOffset == UInt32.max {
            throw BundlePackArchiveError.zip64Unsupported
        }
        guard entryCount < maximumEntries else { throw BundlePackArchiveError.archiveTooLarge }

        var entries: [Entry] = []
        entries.reserveCapacity(entryCount)
        var offset = Int(centralOffset)

        for _ in 0..<entryCount {
            guard offset >= 0,
                  offset + 46 <= data.count,
                  data.uint32LE(at: offset) == centralFileHeader else {
                throw BundlePackArchiveError.notZip
            }

            let flags = data.uint16LE(at: offset + 8)
            let compression = data.uint16LE(at: offset + 10)
            let compressedSize = data.uint32LE(at: offset + 20)
            let uncompressedSize = data.uint32LE(at: offset + 24)
            let nameLength = Int(data.uint16LE(at: offset + 28))
            let extraLength = Int(data.uint16LE(at: offset + 30))
            let commentLength = Int(data.uint16LE(at: offset + 32))
            let externalAttributes = data.uint32LE(at: offset + 38)
            let localOffset = data.uint32LE(at: offset + 42)

            if compressedSize == UInt32.max || uncompressedSize == UInt32.max || localOffset == UInt32.max {
                throw BundlePackArchiveError.zip64Unsupported
            }

            let nameStart = offset + 46
            let nextOffset = nameStart + nameLength + extraLength + commentLength
            guard nameStart >= 0, nextOffset <= data.count else {
                throw BundlePackArchiveError.notZip
            }

            let nameData = data.subdata(in: nameStart..<(nameStart + nameLength))
            guard let path = String(data: nameData, encoding: .utf8), !path.isEmpty else {
                throw BundlePackArchiveError.invalidEntry("Unknown entry")
            }

            entries.append(
                Entry(
                    path: path,
                    flags: flags,
                    compressionMethod: compression,
                    compressedSize: UInt64(compressedSize),
                    uncompressedSize: UInt64(uncompressedSize),
                    localHeaderOffset: UInt64(localOffset),
                    externalAttributes: externalAttributes
                )
            )
            offset = nextOffset
        }

        guard offset <= Int(centralOffset) + Int(centralSize) else {
            throw BundlePackArchiveError.notZip
        }
        return entries
    }

    private static func validate(entries: [Entry], archiveSize: UInt64) throws {
        var expandedSize: UInt64 = 0
        var outputPaths = Set<String>()
        var filePaths = Set<String>()

        for entry in entries {
            guard isSafeArchivePath(entry.path) else {
                throw BundlePackArchiveError.unsafeEntry(entry.path)
            }
            let outputPath = canonicalOutputPath(entry.path)
            guard !outputPath.isEmpty, outputPaths.insert(outputPath).inserted else {
                throw BundlePackArchiveError.duplicateEntry(entry.path)
            }
            if !entry.path.hasSuffix("/") {
                filePaths.insert(outputPath)
            }
            if entry.flags & 0x0001 != 0 {
                throw BundlePackArchiveError.encryptedEntry(entry.path)
            }
            guard entry.compressionMethod == 0 || entry.compressionMethod == 8 else {
                throw BundlePackArchiveError.unsupportedCompression(entry.path)
            }

            let unixMode = UInt16((entry.externalAttributes >> 16) & 0xffff)
            if unixMode & 0xf000 == 0xa000 {
                throw BundlePackArchiveError.unsafeEntry(entry.path)
            }

            let (sum, overflow) = expandedSize.addingReportingOverflow(entry.uncompressedSize)
            guard !overflow else { throw BundlePackArchiveError.archiveTooLarge }
            expandedSize = sum
        }

        for path in outputPaths {
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            guard components.count > 1 else { continue }
            var parent = ""
            for component in components.dropLast() {
                parent = parent.isEmpty ? String(component) : "\(parent)/\(component)"
                if filePaths.contains(parent) {
                    throw BundlePackArchiveError.duplicateEntry(path)
                }
            }
        }

        guard expandedSize <= maximumExpandedSize else {
            throw BundlePackArchiveError.archiveTooLarge
        }
        if archiveSize > 0, expandedSize > 1_024 * 1_024 * 1_024,
           expandedSize / archiveSize > 1_000 {
            throw BundlePackArchiveError.archiveTooLarge
        }
    }

    private static func isSafeArchivePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !path.contains(":"),
              !path.contains("\0") else {
            return false
        }
        let pathWithoutDirectoryMarker = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard !pathWithoutDirectoryMarker.isEmpty else { return false }
        let components = pathWithoutDirectoryMarker.split(separator: "/", omittingEmptySubsequences: false)
        return !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
            && components.first != "~"
    }

    private static func canonicalOutputPath(_ path: String) -> String {
        let withoutDirectoryMarker = path.hasSuffix("/") ? String(path.dropLast()) : path
        return withoutDirectoryMarker
            .precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func storedData(for entry: Entry, in data: Data) throws -> Data {
        guard entry.uncompressedSize <= maximumMetadataSize else {
            throw BundlePackArchiveError.archiveTooLarge
        }
        guard entry.compressionMethod == 0, entry.compressedSize == entry.uncompressedSize else {
            throw BundlePackArchiveError.unsupportedCompression(entry.path)
        }

        let offset = Int(entry.localHeaderOffset)
        guard offset >= 0,
              offset + 30 <= data.count,
              data.uint32LE(at: offset) == localFileHeader else {
            throw BundlePackArchiveError.invalidEntry(entry.path)
        }
        let nameLength = Int(data.uint16LE(at: offset + 26))
        let extraLength = Int(data.uint16LE(at: offset + 28))
        let start = offset + 30 + nameLength + extraLength
        let end = start + Int(entry.compressedSize)
        guard start >= 0, end <= data.count else {
            throw BundlePackArchiveError.invalidEntry(entry.path)
        }
        return data.subdata(in: start..<end)
    }
}

private extension Data {
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
}
