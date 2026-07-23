import Foundation

struct BundlePackOperationProgress: Sendable {
    let fractionCompleted: Double
    let message: String

    init(fractionCompleted: Double, message: String) {
        self.fractionCompleted = min(max(fractionCompleted, 0), 1)
        self.message = message
    }
}

typealias BundlePackProgressHandler = @Sendable (BundlePackOperationProgress) -> Void

enum BundlePackIconValidator {
    private static let pngSignature = Data([137, 80, 78, 71, 13, 10, 26, 10])
    private static let ihdr = Data("IHDR".utf8)
    static let maximumSize = 16 * 1_024 * 1_024

    static func isValidPNG(_ data: Data) -> Bool {
        guard data.count >= 24,
              data.count <= maximumSize,
              data.prefix(pngSignature.count) == pngSignature,
              data.subdata(in: 12..<16) == ihdr else {
            return false
        }

        return data.uint32BE(at: 16) == 1_024 && data.uint32BE(at: 20) == 1_024
    }
}

enum BundlePackAnimationValidator {
    static let path = "animation.gif"
    static let mediaType = "image/gif"
    static let maximumSize = 16 * 1_024 * 1_024
    static let maximumCanvasDimension = 1_024
    static let maximumFrames = 120
    static let maximumTotalPixels = 100_000_000

    static func isGIF(_ data: Data) -> Bool {
        data.count >= 6 && (data.prefix(6) == Data("GIF87a".utf8) || data.prefix(6) == Data("GIF89a".utf8))
    }

    static func isValidGIF(_ data: Data) -> Bool {
        guard data.count <= maximumSize, isGIF(data) else { return false }

        var offset = 6
        guard let canvasWidth = readUInt16(from: data, offset: &offset),
              let canvasHeight = readUInt16(from: data, offset: &offset),
              canvasWidth > 0,
              canvasHeight > 0,
              canvasWidth <= maximumCanvasDimension,
              canvasHeight <= maximumCanvasDimension,
              let packed = readByte(from: data, offset: &offset),
              readByte(from: data, offset: &offset) != nil,
              readByte(from: data, offset: &offset) != nil else {
            return false
        }

        if packed & 0x80 != 0 {
            let tableBytes = 3 * (1 << (Int(packed & 0x07) + 1))
            guard skip(tableBytes, in: data, offset: &offset) else { return false }
        }

        let canvasPixels = canvasWidth * canvasHeight
        var frameCount = 0
        while let block = readByte(from: data, offset: &offset) {
            switch block {
            case 0x21:
                guard let label = readByte(from: data, offset: &offset) else { return false }
                if label == 0xf9 {
                    guard readByte(from: data, offset: &offset) == 4,
                          skip(4, in: data, offset: &offset),
                          readByte(from: data, offset: &offset) == 0 else {
                        return false
                    }
                } else if !skipSubBlocks(in: data, offset: &offset, requiresData: false) {
                    return false
                }
            case 0x2c:
                guard let left = readUInt16(from: data, offset: &offset),
                      let top = readUInt16(from: data, offset: &offset),
                      let width = readUInt16(from: data, offset: &offset),
                      let height = readUInt16(from: data, offset: &offset),
                      width > 0,
                      height > 0,
                      left + width <= canvasWidth,
                      top + height <= canvasHeight,
                      let imagePacked = readByte(from: data, offset: &offset) else {
                    return false
                }
                if imagePacked & 0x80 != 0 {
                    let tableBytes = 3 * (1 << (Int(imagePacked & 0x07) + 1))
                    guard skip(tableBytes, in: data, offset: &offset) else { return false }
                }
                guard let minimumCodeSize = readByte(from: data, offset: &offset),
                      (2...8).contains(minimumCodeSize),
                      skipSubBlocks(in: data, offset: &offset, requiresData: true) else {
                    return false
                }
                frameCount += 1
                guard frameCount <= maximumFrames,
                      canvasPixels * frameCount <= maximumTotalPixels else {
                    return false
                }
            case 0x3b:
                return offset == data.count && frameCount >= 2
            default:
                return false
            }
        }
        return false
    }

    private static func readByte(from data: Data, offset: inout Int) -> Int? {
        guard offset < data.count else { return nil }
        defer { offset += 1 }
        return Int(data[offset])
    }

    private static func readUInt16(from data: Data, offset: inout Int) -> Int? {
        guard let low = readByte(from: data, offset: &offset),
              let high = readByte(from: data, offset: &offset) else {
            return nil
        }
        return low | (high << 8)
    }

    private static func skip(_ count: Int, in data: Data, offset: inout Int) -> Bool {
        guard count >= 0, offset <= data.count - count else { return false }
        offset += count
        return true
    }

    private static func skipSubBlocks(
        in data: Data,
        offset: inout Int,
        requiresData: Bool
    ) -> Bool {
        var total = 0
        while let count = readByte(from: data, offset: &offset) {
            if count == 0 { return !requiresData || total > 0 }
            guard skip(count, in: data, offset: &offset) else { return false }
            total += count
        }
        return false
    }
}

struct BundlePackAnimationMetadata: Codable, Sendable {
    let path: String
    let mediaType: String

    static let gif = Self(
        path: BundlePackAnimationValidator.path,
        mediaType: BundlePackAnimationValidator.mediaType
    )

    var isSupportedGIF: Bool {
        path == BundlePackAnimationValidator.path
            && mediaType == BundlePackAnimationValidator.mediaType
    }
}

struct BundlePackManifest: Codable, Sendable {
    static let formatIdentifier = "com.tuki0918.bundlepack"
    static let staticFormatVersion = 1
    static let animatedFormatVersion = 2
    static let currentFormatVersion = staticFormatVersion
    static let maximumTitleBytes = 256
    static let maximumPackageVersionBytes = 64
    static let maximumAuthorBytes = 256
    static let maximumSummaryBytes = 4_096

    let format: String
    let formatVersion: Int
    let title: String
    let packageVersion: String
    let author: String
    let summary: String
    let createdAt: Date
    let files: [BundlePackFile]
    let animation: BundlePackAnimationMetadata?

    init(
        title: String,
        packageVersion: String,
        author: String,
        summary: String,
        createdAt: Date = Date(),
        files: [BundlePackFile],
        animation: BundlePackAnimationMetadata? = nil
    ) {
        self.format = Self.formatIdentifier
        self.formatVersion = animation == nil ? Self.staticFormatVersion : Self.animatedFormatVersion
        self.title = title
        self.packageVersion = packageVersion
        self.author = author
        self.summary = summary
        self.createdAt = createdAt
        self.files = files
        self.animation = animation
    }

    static func hasValidDisplayMetadata(
        title: String,
        packageVersion: String,
        author: String,
        summary: String
    ) -> Bool {
        isValidDisplayText(title, maximumBytes: maximumTitleBytes, allowsEmpty: false)
            && isValidDisplayText(packageVersion, maximumBytes: maximumPackageVersionBytes)
            && isValidDisplayText(author, maximumBytes: maximumAuthorBytes)
            && isValidDisplayText(summary, maximumBytes: maximumSummaryBytes)
    }

    var hasValidDisplayMetadata: Bool {
        Self.hasValidDisplayMetadata(
            title: title,
            packageVersion: packageVersion,
            author: author,
            summary: summary
        )
    }

    func hasValidAnimationLayout(hasAnimationEntry: Bool) -> Bool {
        switch formatVersion {
        case Self.staticFormatVersion:
            return animation == nil && !hasAnimationEntry
        case Self.animatedFormatVersion:
            return animation?.isSupportedGIF == true && hasAnimationEntry
        default:
            return false
        }
    }

    private static func isValidDisplayText(
        _ value: String,
        maximumBytes: Int,
        allowsEmpty: Bool = true
    ) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (allowsEmpty || !trimmed.isEmpty),
              value.utf8.count <= maximumBytes else {
            return false
        }
        return value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }
}

struct BundlePackFile: Codable, Hashable, Identifiable, Sendable {
    let path: String
    let size: UInt64

    var id: String { path }
}

struct BundlePackArchiveInfo: Sendable {
    let url: URL
    let manifest: BundlePackManifest
    let iconData: Data
    let animationData: Data?
    let payloadFiles: [BundlePackFile]
    let archiveSize: UInt64
    let expandedSize: UInt64
    let archiveDigest: Data
}

private extension Data {
    func uint32BE(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        return (UInt32(self[offset]) << 24)
            | (UInt32(self[offset + 1]) << 16)
            | (UInt32(self[offset + 2]) << 8)
            | UInt32(self[offset + 3])
    }
}
