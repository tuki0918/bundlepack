import Foundation

struct BundlePackManifest: Codable, Sendable {
    static let formatIdentifier = "com.tuki0918.bundlepack"
    static let currentFormatVersion = 1

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
}
