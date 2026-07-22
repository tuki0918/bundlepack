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
    private static let maximumSize = 16 * 1_024 * 1_024

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

struct BundlePackManifest: Codable, Sendable {
    static let formatIdentifier = "com.tuki0918.bundlepack"
    static let currentFormatVersion = 1
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

    init(
        title: String,
        packageVersion: String,
        author: String,
        summary: String,
        createdAt: Date = Date(),
        files: [BundlePackFile]
    ) {
        self.format = Self.formatIdentifier
        self.formatVersion = Self.currentFormatVersion
        self.title = title
        self.packageVersion = packageVersion
        self.author = author
        self.summary = summary
        self.createdAt = createdAt
        self.files = files
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
