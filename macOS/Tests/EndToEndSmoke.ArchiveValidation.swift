import Foundation

extension EndToEndSmoke {
    static func runArchiveValidationScenarios(
        root: URL,
        plainArchive: URL,
        plainData: Data,
        icon: URL,
        extractParent: URL
    ) throws {
        let fileManager = FileManager.default
        let reorderedArchive = root.appendingPathComponent("Reordered-Icon.bundlepack")
        let reorderedStaging = root.appendingPathComponent("reordered-icon-staging", isDirectory: true)
        try fileManager.createDirectory(at: reorderedStaging, withIntermediateDirectories: true)
        try run(
            executable: "/usr/bin/unzip",
            arguments: ["-qq", plainArchive.path, "-d", reorderedStaging.path],
            currentDirectory: nil
        )
        try run(
            executable: "/usr/bin/zip",
            arguments: ["-0", "-X", "-q", reorderedArchive.path, "manifest.json", "icon.png"],
            currentDirectory: reorderedStaging
        )
        try run(
            executable: "/usr/bin/zip",
            arguments: ["-r", "-X", "-q", reorderedArchive.path, "payload"],
            currentDirectory: reorderedStaging
        )
        _ = try ZipArchiveInspector.inspect(reorderedArchive)
        do {
            _ = try ZipArchiveInspector.embeddedIcon(in: reorderedArchive)
            throw TestError("The thumbnail reader parsed a package whose icon was not the leading entry.")
        } catch BundlePackArchiveError.invalidIcon {
            // Expected: automatic previews use only the bounded leading-icon path.
        }

        let dishonestSizeArchive = root.appendingPathComponent("Dishonest-Size.bundlepack")
        let dishonestStaging = root.appendingPathComponent("dishonest-size-staging", isDirectory: true)
        let dishonestPayload = dishonestStaging.appendingPathComponent("payload", isDirectory: true)
        try fileManager.createDirectory(at: dishonestPayload, withIntermediateDirectories: true)
        try fileManager.copyItem(at: icon, to: dishonestStaging.appendingPathComponent("icon.png"))
        let dishonestManifest = BundlePackManifest(
            title: "Dishonest Size",
            packageVersion: "1",
            author: "",
            summary: "",
            files: [BundlePackFile(path: "large.bin", size: 1)]
        )
        let dishonestEncoder = JSONEncoder()
        dishonestEncoder.dateEncodingStrategy = .iso8601
        try dishonestEncoder.encode(dishonestManifest).write(
            to: dishonestStaging.appendingPathComponent("manifest.json"),
            options: .atomic
        )
        try Data(repeating: 0, count: 16 * 1_024 * 1_024).write(
            to: dishonestPayload.appendingPathComponent("large.bin"),
            options: .atomic
        )
        try run(
            executable: "/usr/bin/zip",
            arguments: ["-0", "-X", "-q", dishonestSizeArchive.path, "icon.png", "manifest.json"],
            currentDirectory: dishonestStaging
        )
        try run(
            executable: "/usr/bin/zip",
            arguments: ["-r", "-X", "-q", dishonestSizeArchive.path, "payload"],
            currentDirectory: dishonestStaging
        )
        try patchUncompressedSize(
            in: dishonestSizeArchive,
            entryPath: "payload/large.bin",
            replacement: 1
        )
        let dishonestInfo = try ZipArchiveInspector.inspect(dishonestSizeArchive)
        do {
            _ = try PackageBuilder.extract(dishonestInfo, to: extractParent)
            throw TestError("A payload that expanded beyond its declared size was extracted.")
        } catch BundlePackArchiveError.archiveTooLarge {
            // Expected: bounded raw-DEFLATE validation stops before external extraction.
        }

        let trailingDataArchive = root.appendingPathComponent("Trailing-Data.bundlepack")
        var trailingData = plainData
        trailingData.append(Data("unexpected trailing data".utf8))
        try trailingData.write(to: trailingDataArchive, options: .atomic)
        do {
            _ = try ZipArchiveInspector.inspect(trailingDataArchive)
            throw TestError("A ZIP with data appended after its declared comment was accepted.")
        } catch BundlePackArchiveError.notZip {
            // Expected: the ZIP envelope must account for the complete file.
        }

        let unexpectedRootArchive = root.appendingPathComponent("Unexpected-Root.bundlepack")
        let unexpectedRootStaging = root.appendingPathComponent("unexpected-root-staging", isDirectory: true)
        try createModifiedArchive(
            from: plainArchive,
            to: unexpectedRootArchive,
            stagingAt: unexpectedRootStaging
        ) { staging in
            try Data("not part of BundlePack".utf8).write(to: staging.appendingPathComponent("note.txt"))
        }
        try run(
            executable: "/usr/bin/zip",
            arguments: ["-X", "-q", unexpectedRootArchive.path, "note.txt"],
            currentDirectory: unexpectedRootStaging
        )
        do {
            _ = try ZipArchiveInspector.inspect(unexpectedRootArchive)
            throw TestError("A file outside the BundlePack root layout was accepted.")
        } catch BundlePackArchiveError.invalidEntry {
            // Expected: only icon.png, manifest.json, and payload/ are allowed.
        }

        let manifestMismatchArchive = root.appendingPathComponent("Manifest-Mismatch.bundlepack")
        try createManifestMismatchArchive(
            from: plainArchive,
            to: manifestMismatchArchive,
            stagingAt: root.appendingPathComponent("manifest-mismatch-staging", isDirectory: true)
        )
        do {
            _ = try ZipArchiveInspector.inspect(manifestMismatchArchive)
            throw TestError("A manifest that disagrees with the payload was accepted.")
        } catch BundlePackArchiveError.invalidManifest {
            // Expected: metadata must describe the actual payload exactly.
        }

        let invalidIconArchive = root.appendingPathComponent("Invalid-Icon.bundlepack")
        try createModifiedArchive(
            from: plainArchive,
            to: invalidIconArchive,
            stagingAt: root.appendingPathComponent("invalid-icon-staging", isDirectory: true)
        ) { staging in
            try Data("not a PNG".utf8).write(
                to: staging.appendingPathComponent("icon.png"),
                options: .atomic
            )
        }
        do {
            _ = try ZipArchiveInspector.inspect(invalidIconArchive)
            throw TestError("A package with an invalid icon was accepted.")
        } catch BundlePackArchiveError.invalidIcon {
            // Expected: icons use one portable representation on both platforms.
        }

        let damagedMetadataArchive = root.appendingPathComponent("Damaged-Metadata.bundlepack")
        var damagedMetadata = plainData
        let damagedMetadataCount = replaceAll(
            in: &damagedMetadata,
            source: Data("Plain Demo".utf8),
            replacement: Data("Plaxx Demo".utf8)
        )
        try require(damagedMetadataCount == 1, "The metadata corruption fixture could not be prepared.")
        try damagedMetadata.write(to: damagedMetadataArchive, options: .atomic)
        do {
            _ = try ZipArchiveInspector.inspect(damagedMetadataArchive)
            throw TestError("Metadata with an invalid ZIP CRC was accepted.")
        } catch BundlePackArchiveError.invalidEntry {
            // Expected: stored metadata is protected by the ZIP CRC.
        }
    }
}
