import Foundation

extension EndToEndSmoke {
    struct FormatV1Expectations: Decodable {
        let formatIdentifier: String
        let manifestVersion: Int
        let animation: Animation
        let minimumPasswordCharacters: Int
        let container: Container
        let limits: Limits
        let displayMetadataBytes: DisplayMetadataBytes

        struct Animation: Decodable {
            let manifestVersion: Int
            let path: String
            let mediaType: String
            let maximumCanvasDimension: Int
            let maximumFrames: Int
            let maximumTotalPixels: Int
        }

        struct Container: Decodable {
            let magic: String
            let version: UInt16
            let flags: UInt16
            let fixedHeaderSize: Int
            let pbkdf2Iterations: UInt32
            let plaintextChunkSize: UInt32
        }

        struct Limits: Decodable {
            let maximumAcceptedEntries: Int
            let maximumExpandedBytes: UInt64
            let maximumMetadataBytes: UInt64
            let maximumInputFileBytes: UInt64
        }

        struct DisplayMetadataBytes: Decodable {
            let title: Int
            let packageVersion: Int
            let author: Int
            let summary: Int
        }
    }

    static func loadAndVerifyFormatExpectations(
        at url: URL
    ) throws -> FormatV1Expectations {
        let expectations = try JSONDecoder().decode(
            FormatV1Expectations.self,
            from: Data(contentsOf: url)
        )

        try require(
            expectations.formatIdentifier == BundlePackManifest.formatIdentifier,
            "The Swift format identifier differs from Fixtures/FormatV1.json."
        )
        try require(
            expectations.manifestVersion == BundlePackManifest.currentFormatVersion,
            "The Swift manifest version differs from Fixtures/FormatV1.json."
        )
        try require(
            expectations.animation.manifestVersion == BundlePackManifest.animatedFormatVersion
                && expectations.animation.path == BundlePackAnimationValidator.path
                && expectations.animation.mediaType == BundlePackAnimationValidator.mediaType
                && expectations.animation.maximumCanvasDimension
                    == BundlePackAnimationValidator.maximumCanvasDimension
                && expectations.animation.maximumFrames == BundlePackAnimationValidator.maximumFrames
                && expectations.animation.maximumTotalPixels
                    == BundlePackAnimationValidator.maximumTotalPixels,
            "The Swift animation contract differs from Fixtures/FormatV1.json."
        )
        try require(
            expectations.minimumPasswordCharacters
                == BundlePackEncryptedContainer.minimumPasswordCharacters,
            "The Swift password minimum differs from Fixtures/FormatV1.json."
        )
        try require(
            Data(expectations.container.magic.utf8) == BundlePackEncryptedContainer.magic,
            "The Swift encrypted-container magic differs from Fixtures/FormatV1.json."
        )
        try require(
            expectations.container.version == BundlePackEncryptedContainer.version
                && expectations.container.flags == BundlePackEncryptedContainer.flags
                && expectations.container.fixedHeaderSize == BundlePackEncryptedContainer.fixedHeaderSize
                && expectations.container.pbkdf2Iterations == BundlePackEncryptedContainer.iterations
                && expectations.container.plaintextChunkSize == BundlePackEncryptedContainer.chunkSize,
            "The Swift encrypted-container constants differ from Fixtures/FormatV1.json."
        )
        try require(
            expectations.limits.maximumAcceptedEntries == ZipArchiveInspector.maximumEntries - 1
                && expectations.limits.maximumExpandedBytes == ZipArchiveInspector.maximumExpandedSize
                && expectations.limits.maximumMetadataBytes == ZipArchiveInspector.maximumMetadataSize
                && expectations.limits.maximumMetadataBytes
                    == UInt64(BundlePackIconValidator.maximumSize)
                && expectations.limits.maximumInputFileBytes == PackageBuilder.maximumInputFileBytes
                && expectations.limits.maximumExpandedBytes == PackageBuilder.maximumTotalInputBytes,
            "The Swift package limits differ from Fixtures/FormatV1.json."
        )
        try require(
            expectations.displayMetadataBytes.title == BundlePackManifest.maximumTitleBytes
                && expectations.displayMetadataBytes.packageVersion
                    == BundlePackManifest.maximumPackageVersionBytes
                && expectations.displayMetadataBytes.author == BundlePackManifest.maximumAuthorBytes
                && expectations.displayMetadataBytes.summary == BundlePackManifest.maximumSummaryBytes,
            "The Swift display metadata limits differ from Fixtures/FormatV1.json."
        )

        return expectations
    }

    static func verifyEncryptedHeader(
        _ data: Data,
        expectations: FormatV1Expectations
    ) throws {
        let container = expectations.container
        try require(
            data.count >= container.fixedHeaderSize
                && data.prefix(container.magic.utf8.count) == Data(container.magic.utf8),
            "The encrypted output does not use the expected v1 header."
        )
        try require(
            formatUInt16LE(data, at: 8) == container.version
                && formatUInt16LE(data, at: 10) == container.flags
                && formatUInt32LE(data, at: 12) == container.pbkdf2Iterations
                && formatUInt32LE(data, at: 16) == container.plaintextChunkSize,
            "The encrypted output header differs from Fixtures/FormatV1.json."
        )

        let iconSize = Int(formatUInt32LE(data, at: 32))
        let pngSignature = Data([137, 80, 78, 71, 13, 10, 26, 10])
        try require(
            iconSize >= pngSignature.count
                && data.count >= container.fixedHeaderSize + iconSize
                && data.subdata(
                    in: container.fixedHeaderSize..<(container.fixedHeaderSize + pngSignature.count)
                ) == pngSignature,
            "The encrypted output public icon does not begin after the expected fixed header."
        )
    }

    private static func formatUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func formatUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
