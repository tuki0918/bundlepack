import Foundation
import zlib

extension ZipArchiveInspector {
    private static let endOfCentralDirectory: UInt32 = 0x0605_4b50
    private static let centralFileHeader: UInt32 = 0x0201_4b50
    private static let localFileHeader: UInt32 = 0x0403_4b50
    static let maximumEntries = 10_000
    static let maximumExpandedSize: UInt64 = 20 * 1_024 * 1_024 * 1_024
    static let maximumMetadataSize: UInt64 = 16 * 1_024 * 1_024
    private static let crc32Table: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            crc = crc & 1 == 1 ? 0xedb8_8320 ^ (crc >> 1) : crc >> 1
        }
        return crc
    }

    static func leadingStoredIcon(in url: URL) throws -> Data? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        guard let header = try handle.read(upToCount: 30),
              header.count == 30,
              header.uint32LE(at: 0) == localFileHeader else {
            return nil
        }

        let flags = header.uint16LE(at: 6)
        let compressionMethod = header.uint16LE(at: 8)
        let expectedCRC32 = header.uint32LE(at: 14)
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
        guard crc32(of: iconData) == expectedCRC32 else {
            throw BundlePackArchiveError.invalidEntry("icon.png")
        }
        guard BundlePackIconValidator.isValidPNG(iconData) else {
            throw BundlePackArchiveError.invalidIcon
        }
        return iconData
    }

    struct Entry {
        let path: String
        let flags: UInt16
        let compressionMethod: UInt16
        let crc32: UInt32
        let compressedSize: UInt64
        let uncompressedSize: UInt64
        let localHeaderOffset: UInt64
        let externalAttributes: UInt32
    }

    static func parseEntries(in data: Data) throws -> [Entry] {
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

        let diskNumber = data.uint16LE(at: endOffset + 4)
        let centralDirectoryDisk = data.uint16LE(at: endOffset + 6)
        let entriesOnDisk = data.uint16LE(at: endOffset + 8)
        let entryCount = Int(data.uint16LE(at: endOffset + 10))
        let centralSize = data.uint32LE(at: endOffset + 12)
        let centralOffset = data.uint32LE(at: endOffset + 16)
        let archiveCommentLength = Int(data.uint16LE(at: endOffset + 20))

        guard diskNumber == 0,
              centralDirectoryDisk == 0,
              Int(entriesOnDisk) == entryCount,
              endOffset + 22 + archiveCommentLength == data.count,
              Int(centralOffset) + Int(centralSize) == endOffset else {
            throw BundlePackArchiveError.notZip
        }

        if entryCount == Int(UInt16.max) || centralSize == UInt32.max || centralOffset == UInt32.max {
            throw BundlePackArchiveError.zip64Unsupported
        }
        guard entryCount < maximumEntries else { throw BundlePackArchiveError.archiveTooLarge }

        var entries: [Entry] = []
        entries.reserveCapacity(entryCount)
        var offset = Int(centralOffset)

        for _ in 0..<entryCount {
            try Task.checkCancellation()
            guard offset >= 0,
                  offset + 46 <= data.count,
                  data.uint32LE(at: offset) == centralFileHeader else {
                throw BundlePackArchiveError.notZip
            }

            let flags = data.uint16LE(at: offset + 8)
            let compression = data.uint16LE(at: offset + 10)
            let crc32 = data.uint32LE(at: offset + 16)
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
                    crc32: crc32,
                    compressedSize: UInt64(compressedSize),
                    uncompressedSize: UInt64(uncompressedSize),
                    localHeaderOffset: UInt64(localOffset),
                    externalAttributes: externalAttributes
                )
            )
            offset = nextOffset
        }

        guard offset == Int(centralOffset) + Int(centralSize) else {
            throw BundlePackArchiveError.notZip
        }
        return entries
    }

    static func validate(entries: [Entry], archiveSize: UInt64) throws {
        var expandedSize: UInt64 = 0
        var outputPaths = Set<String>()
        var filePaths = Set<String>()

        for entry in entries {
            try Task.checkCancellation()
            guard isAllowedBundlePackPath(entry.path) else {
                throw BundlePackArchiveError.invalidEntry(entry.path)
            }
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
        return !components.contains(where: {
            $0.isEmpty || $0 == "." || $0 == ".." || !isPortableFilename(String($0))
        })
            && components.first != "~"
    }

    private static func isAllowedBundlePackPath(_ path: String) -> Bool {
        path == "icon.png"
            || path == "manifest.json"
            || path == BundlePackAnimationValidator.path
            || path == "payload/"
            || path.hasPrefix("payload/")
    }

    private static func isPortableFilename(_ name: String) -> Bool {
        let reserved = Set([
            "CON", "PRN", "AUX", "NUL",
            "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
            "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"
        ])
        let forbidden = CharacterSet(charactersIn: "<>:\"/\\|?*")
            .union(.controlCharacters)
        let stem = name.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init)?
            .uppercased() ?? ""
        return !name.isEmpty
            && !name.hasSuffix(" ")
            && !name.hasSuffix(".")
            && name.rangeOfCharacter(from: forbidden) == nil
            && !reserved.contains(stem)
    }

    private static func canonicalOutputPath(_ path: String) -> String {
        let withoutDirectoryMarker = path.hasSuffix("/") ? String(path.dropLast()) : path
        return withoutDirectoryMarker
            .precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func storedData(for entry: Entry, in data: Data) throws -> Data {
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
        let localFlags = data.uint16LE(at: offset + 6)
        let localCompressionMethod = data.uint16LE(at: offset + 8)
        let localCRC32 = data.uint32LE(at: offset + 14)
        let localCompressedSize = UInt64(data.uint32LE(at: offset + 18))
        let localUncompressedSize = UInt64(data.uint32LE(at: offset + 22))
        let nameStart = offset + 30
        let nameEnd = nameStart + nameLength
        let start = offset + 30 + nameLength + extraLength
        let end = start + Int(entry.compressedSize)
        guard nameStart >= 0,
              nameEnd <= data.count,
              let localPath = String(data: data.subdata(in: nameStart..<nameEnd), encoding: .utf8),
              localPath == entry.path,
              localFlags == entry.flags,
              localCompressionMethod == entry.compressionMethod,
              localCRC32 == entry.crc32,
              localCompressedSize == entry.compressedSize,
              localUncompressedSize == entry.uncompressedSize,
              start >= 0,
              end <= data.count else {
            throw BundlePackArchiveError.invalidEntry(entry.path)
        }
        let result = data.subdata(in: start..<end)
        guard crc32(of: result) == entry.crc32 else {
            throw BundlePackArchiveError.invalidEntry(entry.path)
        }
        return result
    }

    static func validateEntryStream(
        _ entry: Entry,
        in data: Data,
        didValidate: (UInt64) -> Void = { _ in }
    ) throws {
        try Task.checkCancellation()
        let range = try compressedDataRange(for: entry, in: data)
        if entry.compressionMethod == 0 {
            guard UInt64(range.count) == entry.uncompressedSize else {
                throw BundlePackArchiveError.invalidEntry(entry.path)
            }
            let actualCRC = data.withUnsafeBytes { bytes -> UInt32 in
                let slice = UnsafeRawBufferPointer(rebasing: bytes[range])
                return crc32(of: slice)
            }
            guard actualCRC == entry.crc32 else {
                throw BundlePackArchiveError.invalidEntry(entry.path)
            }
            didValidate(entry.uncompressedSize)
            return
        }

        guard entry.compressionMethod == 8 else {
            throw BundlePackArchiveError.unsupportedCompression(entry.path)
        }

        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw BundlePackArchiveError.invalidEntry(entry.path)
        }
        defer { inflateEnd(&stream) }

        var expandedSize: UInt64 = 0
        var crc = UInt32.max
        var output = [UInt8](repeating: 0, count: 128 * 1_024)
        var reachedEnd = false

        try data.withUnsafeBytes { archiveBytes in
            guard let archiveBase = archiveBytes.bindMemory(to: Bytef.self).baseAddress else {
                throw BundlePackArchiveError.invalidEntry(entry.path)
            }
            stream.next_in = UnsafeMutablePointer(mutating: archiveBase.advanced(by: range.lowerBound))
            stream.avail_in = uInt(range.count)

            while !reachedEnd {
                try Task.checkCancellation()
                let status = output.withUnsafeMutableBytes { outputBytes -> Int32 in
                    stream.next_out = outputBytes.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(outputBytes.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                let produced = output.count - Int(stream.avail_out)
                if produced > 0 {
                    let (nextSize, overflow) = expandedSize.addingReportingOverflow(UInt64(produced))
                    guard !overflow, nextSize <= entry.uncompressedSize else {
                        throw BundlePackArchiveError.archiveTooLarge
                    }
                    expandedSize = nextSize
                    output.withUnsafeBytes { outputBytes in
                        crc = crc32Update(crc, bytes: UnsafeRawBufferPointer(rebasing: outputBytes[..<produced]))
                    }
                    didValidate(UInt64(produced))
                }

                if status == Z_STREAM_END {
                    reachedEnd = true
                } else if status != Z_OK || (produced == 0 && stream.avail_in == 0) {
                    throw BundlePackArchiveError.invalidEntry(entry.path)
                }
            }
        }

        guard expandedSize == entry.uncompressedSize,
              stream.avail_in == 0,
              crc ^ UInt32.max == entry.crc32 else {
            throw BundlePackArchiveError.invalidEntry(entry.path)
        }
    }

    private static func compressedDataRange(for entry: Entry, in data: Data) throws -> Range<Int> {
        let offset = Int(entry.localHeaderOffset)
        guard offset >= 0,
              offset + 30 <= data.count,
              data.uint32LE(at: offset) == localFileHeader else {
            throw BundlePackArchiveError.invalidEntry(entry.path)
        }
        let localFlags = data.uint16LE(at: offset + 6)
        let localCompression = data.uint16LE(at: offset + 8)
        let localCRC = data.uint32LE(at: offset + 14)
        let localCompressedSize = UInt64(data.uint32LE(at: offset + 18))
        let localUncompressedSize = UInt64(data.uint32LE(at: offset + 22))
        let nameLength = Int(data.uint16LE(at: offset + 26))
        let extraLength = Int(data.uint16LE(at: offset + 28))
        let nameStart = offset + 30
        let nameEnd = nameStart + nameLength
        let start = nameEnd + extraLength
        let end = start + Int(entry.compressedSize)
        let usesDataDescriptor = entry.flags & 0x0008 != 0
        guard nameStart >= 0,
              nameEnd <= data.count,
              start >= nameEnd,
              end >= start,
              end <= data.count,
              let localPath = String(data: data.subdata(in: nameStart..<nameEnd), encoding: .utf8),
              localPath == entry.path,
              localFlags == entry.flags,
              localCompression == entry.compressionMethod,
              usesDataDescriptor
                || (localCRC == entry.crc32
                    && localCompressedSize == entry.compressedSize
                    && localUncompressedSize == entry.uncompressedSize) else {
            throw BundlePackArchiveError.invalidEntry(entry.path)
        }
        return start..<end
    }

    private static func crc32(of data: Data) -> UInt32 {
        data.withUnsafeBytes { crc32(of: $0) }
    }

    private static func crc32(of bytes: UnsafeRawBufferPointer) -> UInt32 {
        crc32Update(UInt32.max, bytes: bytes) ^ UInt32.max
    }

    private static func crc32Update(_ initial: UInt32, bytes: UnsafeRawBufferPointer) -> UInt32 {
        var crc = initial
        for byte in bytes {
            let index = Int((crc ^ UInt32(byte)) & 0xff)
            crc = crc32Table[index] ^ (crc >> 8)
        }
        return crc
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
