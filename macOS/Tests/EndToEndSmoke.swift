import AppKit
import Foundation

@main
enum EndToEndSmoke {
    static func main() async throws {
        guard CommandLine.arguments.count == 3 else {
            throw TestError("Paths to DefaultPackageIcon.png and FormatV1.json are required.")
        }

        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("BundlePack-Smoke-\(UUID().uuidString)", isDirectory: true)
        let input = root.appendingPathComponent("input", isDirectory: true)
        let nested = input.appendingPathComponent("nested", isDirectory: true)
        let emptyDirectory = input.appendingPathComponent("empty", isDirectory: true)
        let zeroByteFile = input.appendingPathComponent("zero-byte.dat")
        let archive = root.appendingPathComponent("Demo.bundlepack")
        let plainArchive = root.appendingPathComponent("Plain.bundlepack")
        let extractParent = root.appendingPathComponent("extracted", isDirectory: true)
        let decryptedArchive = root.appendingPathComponent("decrypted.zip")
        let icon = URL(fileURLWithPath: CommandLine.arguments[1])
        let formatExpectations = try loadAndVerifyFormatExpectations(
            at: URL(fileURLWithPath: CommandLine.arguments[2])
        )
        let password = "Correct-Horse-Battery-2026!"

        try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: emptyDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: extractParent, withIntermediateDirectories: true)
        try Data("Hello BundlePack\n".utf8).write(to: input.appendingPathComponent("hello.txt"))
        try Data([0, 1, 2, 3, 4, 5]).write(to: nested.appendingPathComponent("data.bin"))
        try Data().write(to: zeroByteFile)
        defer { try? fileManager.removeItem(at: root) }

        let request = PackageCreationRequest(
            title: "Demo Package",
            packageVersion: "1.2.3",
            author: "BundlePack Test",
            summary: "End-to-end smoke test",
            inputURLs: [input],
            iconURL: nil,
            fallbackIconURL: icon,
            encryptionEnabled: true,
            password: password,
            destinationURL: archive
        )

        let progressRecorder = ProgressRecorder()
        let created = try PackageBuilder.create(request) { value in
            progressRecorder.record(value.fractionCompleted)
        }
        guard case .encrypted(let encryptedInfo) = created else {
            throw TestError("The encrypted package was not created in the encrypted format.")
        }
        try require(encryptedInfo.originalArchiveSize > 0, "The original archive size is missing.")

        let encryptedData = try Data(contentsOf: archive, options: [.mappedIfSafe])
        try verifyEncryptedHeader(encryptedData, expectations: formatExpectations)
        try require(encryptedData.prefix(8) == Data("BPKENC01".utf8), "The encrypted container signature is missing.")
        try require(encryptedData.prefix(4) != Data([0x50, 0x4b, 0x03, 0x04]), "A ZIP signature is exposed at the outer container level.")
        try require(encryptedData.range(of: Data("hello.txt".utf8)) == nil, "A file name is exposed as plaintext.")
        try require(encryptedData.range(of: Data("Hello BundlePack".utf8)) == nil, "File content is exposed as plaintext.")

        try BundlePackEncryptedContainer.open(archive, password: password, to: decryptedArchive)
        let reopened = try ZipArchiveInspector.inspect(decryptedArchive)
        try require(reopened.manifest.title == "Demo Package", "The title does not match.")
        try require(reopened.manifest.packageVersion == "1.2.3", "The reopened version does not match.")
        try require(reopened.payloadFiles.count == 3, "The file count does not match.")
        let progressValues = progressRecorder.values
        try require(progressValues.last == 1, "Create progress did not reach 100%.")
        try require(
            zip(progressValues, progressValues.dropFirst()).allSatisfy { $0 <= $1 },
            "Create progress moved backwards."
        )
        try require(!reopened.iconData.isEmpty, "The embedded icon is missing.")
        try require(
            encryptedInfo.iconData == reopened.iconData,
            "The encrypted container's public icon does not match the package icon."
        )

        let extractionProgressRecorder = ProgressRecorder()
        let extracted = try PackageBuilder.extract(
            decryptedArchive,
            to: extractParent
        ) { value in
            extractionProgressRecorder.record(value.fractionCompleted)
        }
        let extractionProgressValues = extractionProgressRecorder.values
        try require(extractionProgressValues.last == 1, "Extraction progress did not reach 100%.")
        try require(
            zip(extractionProgressValues, extractionProgressValues.dropFirst()).allSatisfy { $0 <= $1 },
            "Extraction progress moved backwards."
        )
        let extractedText = extracted
            .appendingPathComponent("input", isDirectory: true)
            .appendingPathComponent("hello.txt")
        try require(fileManager.fileExists(atPath: extractedText.path), "The extracted file is missing.")
        var isEmptyDirectory: ObjCBool = false
        let extractedEmptyDirectory = extracted
            .appendingPathComponent("input", isDirectory: true)
            .appendingPathComponent("empty", isDirectory: true)
        try require(
            fileManager.fileExists(atPath: extractedEmptyDirectory.path, isDirectory: &isEmptyDirectory)
                && isEmptyDirectory.boolValue,
            "An empty directory was not preserved."
        )
        let extractedZeroByteFile = extracted
            .appendingPathComponent("input", isDirectory: true)
            .appendingPathComponent("zero-byte.dat")
        let zeroByteSize = try extractedZeroByteFile.resourceValues(forKeys: [.fileSizeKey]).fileSize
        try require(zeroByteSize == 0, "A zero-byte file was not preserved.")

        do {
            try BundlePackEncryptedContainer.open(
                archive,
                password: "This-Is-The-Wrong-Password",
                to: root.appendingPathComponent("wrong.zip")
            )
            throw TestError("An incorrect password was not rejected.")
        } catch BundlePackEncryptionError.wrongPasswordOrTampered {
            // Expected.
        }

        let plainRequest = PackageCreationRequest(
            title: "Plain Demo",
            packageVersion: "1.0",
            author: "",
            summary: "",
            inputURLs: [input],
            iconURL: nil,
            fallbackIconURL: icon,
            encryptionEnabled: false,
            password: "",
            destinationURL: plainArchive
        )
        try Data("stale package data".utf8).write(to: plainArchive)
        let plainResult = try PackageBuilder.create(plainRequest)
        guard case .unencrypted(let plainInfo) = plainResult else {
            throw TestError("The unencrypted package was not created in the ZIP-compatible format.")
        }
        let plainData = try Data(contentsOf: plainArchive, options: [.mappedIfSafe])
        try require(plainData.prefix(4) == Data([0x50, 0x4b, 0x03, 0x04]), "The unencrypted package is not ZIP-compatible.")
        try require(plainData.range(of: Data("hello.txt".utf8)) != nil, "The file name is missing from the unencrypted ZIP.")
        try require(plainInfo.payloadFiles.count == 3, "The unencrypted ZIP contents could not be reopened.")
        let lightweightIconData = try ZipArchiveInspector.embeddedIcon(in: plainArchive)
        try require(
            lightweightIconData == plainInfo.iconData,
            "The lightweight thumbnail icon reader returned different icon data."
        )
        try require(
            BundlePackIconValidator.isValidPNG(plainInfo.iconData),
            "The generated package icon is not a valid 1024 × 1024 PNG."
        )
        let leftoverPlainArchives = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix(".Plain.bundlepack.")
                && $0.pathExtension == "tmp"
        }
        try require(leftoverPlainArchives.isEmpty, "A temporary unencrypted package was not removed.")

        try runArchiveValidationScenarios(
            root: root,
            plainArchive: plainArchive,
            plainData: plainData,
            icon: icon,
            extractParent: extractParent
        )

        let unsafeTitleArchive = root.appendingPathComponent("Unsafe-Title.bundlepack")
        let unsafeTitleRequest = PackageCreationRequest(
            title: "..",
            packageVersion: "1.0",
            author: "",
            summary: "",
            inputURLs: [input.appendingPathComponent("hello.txt")],
            iconURL: nil,
            fallbackIconURL: icon,
            encryptionEnabled: false,
            password: "",
            destinationURL: unsafeTitleArchive
        )
        _ = try PackageBuilder.create(unsafeTitleRequest)
        let safeTitleDestination = try PackageBuilder.extract(unsafeTitleArchive, to: extractParent)
        try require(
            safeTitleDestination.deletingLastPathComponent().standardizedFileURL == extractParent.standardizedFileURL
                && safeTitleDestination.lastPathComponent == "BundlePack",
            "An unsafe package title escaped or changed the extraction parent."
        )

        let firstNameSource = root.appendingPathComponent("first-name-source", isDirectory: true)
        let secondNameSource = root.appendingPathComponent("second-name-source", isDirectory: true)
        try fileManager.createDirectory(at: firstNameSource, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: secondNameSource, withIntermediateDirectories: true)
        let lowercaseName = firstNameSource.appendingPathComponent("sample.txt")
        let uppercaseName = secondNameSource.appendingPathComponent("SAMPLE.txt")
        try Data("lowercase".utf8).write(to: lowercaseName)
        try Data("uppercase".utf8).write(to: uppercaseName)
        let normalizedNamesArchive = root.appendingPathComponent("Normalized-Names.bundlepack")
        let normalizedNamesRequest = PackageCreationRequest(
            title: "Normalized Names",
            packageVersion: "1.0",
            author: "",
            summary: "",
            inputURLs: [lowercaseName, uppercaseName],
            iconURL: nil,
            fallbackIconURL: icon,
            encryptionEnabled: false,
            password: "",
            destinationURL: normalizedNamesArchive
        )
        guard case .unencrypted(let normalizedNamesInfo) = try PackageBuilder.create(normalizedNamesRequest) else {
            throw TestError("The normalized-name package was not created.")
        }
        try require(normalizedNamesInfo.payloadFiles.count == 2, "Case-colliding input names were not preserved.")
        let normalizedNameKeys = Set(normalizedNamesInfo.payloadFiles.map {
            $0.path.precomposedStringWithCanonicalMapping.lowercased()
        })
        try require(normalizedNameKeys.count == 2, "Case-colliding input names were not made unique.")

        let sameNameFileParent = root.appendingPathComponent("same-name-file", isDirectory: true)
        let sameNameFolderParent = root.appendingPathComponent("same-name-folder", isDirectory: true)
        try fileManager.createDirectory(at: sameNameFileParent, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: sameNameFolderParent, withIntermediateDirectories: true)
        let sameNameFile = sameNameFileParent.appendingPathComponent("shared")
        let sameNameFolder = sameNameFolderParent.appendingPathComponent("shared", isDirectory: true)
        try Data("file".utf8).write(to: sameNameFile)
        try fileManager.createDirectory(at: sameNameFolder, withIntermediateDirectories: true)
        try Data("folder child".utf8).write(to: sameNameFolder.appendingPathComponent("inside.txt"))
        let sameNameArchive = root.appendingPathComponent("Same-Name.bundlepack")
        let sameNameRequest = PackageCreationRequest(
            title: "Same Name",
            packageVersion: "1.0",
            author: "",
            summary: "",
            inputURLs: [sameNameFile, sameNameFolder],
            iconURL: nil,
            fallbackIconURL: icon,
            encryptionEnabled: false,
            password: "",
            destinationURL: sameNameArchive
        )
        guard case .unencrypted(let sameNameInfo) = try PackageBuilder.create(sameNameRequest) else {
            throw TestError("The same-name package was not created.")
        }
        try require(
            sameNameInfo.payloadFiles.contains { $0.path == "shared" }
                && sameNameInfo.payloadFiles.contains { $0.path == "shared 2/inside.txt" },
            "A same-name file and folder were not preserved with unique output names."
        )

        let cancellationInput = root.appendingPathComponent("cancellation-input.bin")
        FileManager.default.createFile(atPath: cancellationInput.path, contents: nil)
        let cancellationHandle = try FileHandle(forWritingTo: cancellationInput)
        try cancellationHandle.truncate(atOffset: 64 * 1_024 * 1_024)
        try cancellationHandle.close()
        let cancelledArchive = root.appendingPathComponent("Cancelled.bundlepack")
        let cancellationRequest = PackageCreationRequest(
            title: "Cancelled",
            packageVersion: "1.0",
            author: "",
            summary: "",
            inputURLs: [cancellationInput],
            iconURL: nil,
            fallbackIconURL: icon,
            encryptionEnabled: false,
            password: "",
            destinationURL: cancelledArchive
        )
        let cancellationTask = Task.detached {
            try PackageBuilder.create(cancellationRequest)
        }
        cancellationTask.cancel()
        do {
            _ = try await cancellationTask.value
            throw TestError("A cancelled package creation completed.")
        } catch is CancellationError {
            // Expected.
        }
        try require(
            !fileManager.fileExists(atPath: cancelledArchive.path),
            "A cancelled package creation left a destination file."
        )

        let duplicateFirst = root.appendingPathComponent("alpha.txt")
        let duplicateSecond = root.appendingPathComponent("bravo.txt")
        let duplicateArchive = root.appendingPathComponent("Duplicate-Paths.bundlepack")
        try Data("alpha".utf8).write(to: duplicateFirst)
        try Data("bravo".utf8).write(to: duplicateSecond)
        let duplicateRequest = PackageCreationRequest(
            title: "Duplicate Paths",
            packageVersion: "1.0",
            author: "",
            summary: "",
            inputURLs: [duplicateFirst, duplicateSecond],
            iconURL: nil,
            fallbackIconURL: icon,
            encryptionEnabled: false,
            password: "",
            destinationURL: duplicateArchive
        )
        _ = try PackageBuilder.create(duplicateRequest)
        let uniquePathArchiveData = try Data(contentsOf: duplicateArchive)
        var duplicateData = uniquePathArchiveData
        let replacementCount = replaceAll(
            in: &duplicateData,
            source: Data("payload/bravo.txt".utf8),
            replacement: Data("payload/alpha.txt".utf8)
        )
        try require(
            replacementCount >= 2,
            "The duplicate-path fixture could not be prepared (replaced \(replacementCount) entries)."
        )
        try duplicateData.write(to: duplicateArchive, options: .atomic)
        try requireDuplicatePathRejected(duplicateArchive)

        let caseCollisionArchive = root.appendingPathComponent("Case-Collision.bundlepack")
        var caseCollisionData = uniquePathArchiveData
        let caseReplacementCount = replaceAll(
            in: &caseCollisionData,
            source: Data("payload/bravo.txt".utf8),
            replacement: Data("payload/ALPHA.txt".utf8)
        )
        try require(
            caseReplacementCount >= 2,
            "The case-collision fixture could not be prepared (replaced \(caseReplacementCount) entries)."
        )
        try caseCollisionData.write(to: caseCollisionArchive, options: .atomic)
        try requireDuplicatePathRejected(caseCollisionArchive)

        let normalizedPathArchive = root.appendingPathComponent("Normalized-Path.bundlepack")
        var normalizedPathData = uniquePathArchiveData
        let normalizedPathReplacementCount = replaceAll(
            in: &normalizedPathData,
            source: Data("payload/bravo.txt".utf8),
            replacement: Data("payload/./abc.txt".utf8)
        )
        try require(
            normalizedPathReplacementCount >= 2,
            "The normalized-path fixture could not be prepared (replaced \(normalizedPathReplacementCount) entries)."
        )
        try normalizedPathData.write(to: normalizedPathArchive, options: .atomic)
        try requireUnsafePathRejected(normalizedPathArchive)

        let symlink = root.appendingPathComponent("unsafe-link")
        try fileManager.createSymbolicLink(at: symlink, withDestinationURL: input.appendingPathComponent("hello.txt"))
        let unsafeRequest = PackageCreationRequest(
            title: "Unsafe",
            packageVersion: "1",
            author: "",
            summary: "",
            inputURLs: [symlink],
            iconURL: nil,
            fallbackIconURL: icon,
            encryptionEnabled: true,
            password: password,
            destinationURL: root.appendingPathComponent("Unsafe.bundlepack")
        )

        do {
            _ = try PackageBuilder.create(unsafeRequest)
            throw TestError("A symbolic link was not rejected.")
        } catch PackageBuilderError.symbolicLink {
            // Expected.
        }

        let packageDirectory = root.appendingPathComponent("package-link-source", isDirectory: true)
        let nestedApplicationContents = packageDirectory
            .appendingPathComponent("Nested.app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
        try fileManager.createDirectory(at: nestedApplicationContents, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(
            at: nestedApplicationContents.appendingPathComponent("private.txt"),
            withDestinationURL: input.appendingPathComponent("hello.txt")
        )
        let nestedLinkRequest = PackageCreationRequest(
            title: "Nested Link",
            packageVersion: "1",
            author: "",
            summary: "",
            inputURLs: [packageDirectory],
            iconURL: nil,
            fallbackIconURL: icon,
            encryptionEnabled: false,
            password: "",
            destinationURL: root.appendingPathComponent("Nested-Link.bundlepack")
        )
        do {
            _ = try PackageBuilder.create(nestedLinkRequest)
            throw TestError("A symbolic link inside a nested application package was not rejected.")
        } catch PackageBuilderError.symbolicLink {
            // Expected: package descendants are validated too.
        }

        let oversizedMetadataRequest = PackageCreationRequest(
            title: String(repeating: "a", count: BundlePackManifest.maximumTitleBytes + 1),
            packageVersion: "1",
            author: "",
            summary: "",
            inputURLs: [input.appendingPathComponent("hello.txt")],
            iconURL: nil,
            fallbackIconURL: icon,
            encryptionEnabled: false,
            password: "",
            destinationURL: root.appendingPathComponent("Oversized-Metadata.bundlepack")
        )
        do {
            _ = try PackageBuilder.create(oversizedMetadataRequest)
            throw TestError("Oversized display metadata was not rejected.")
        } catch PackageBuilderError.invalidMetadata {
            // Expected: UI-facing strings have explicit cross-platform bounds.
        }

        let reservedName = root.appendingPathComponent("CON.txt")
        try Data("reserved".utf8).write(to: reservedName)
        let reservedNameRequest = PackageCreationRequest(
            title: "Reserved Name",
            packageVersion: "1",
            author: "",
            summary: "",
            inputURLs: [reservedName],
            iconURL: nil,
            fallbackIconURL: icon,
            encryptionEnabled: false,
            password: "",
            destinationURL: root.appendingPathComponent("Reserved.bundlepack")
        )
        do {
            _ = try PackageBuilder.create(reservedNameRequest)
            throw TestError("A Windows-reserved file name was not rejected.")
        } catch PackageBuilderError.unsupportedFilename {
            // Expected: packages must remain extractable on macOS and Windows.
        }

        let replacementArchive = root.appendingPathComponent("Replacement.bundlepack")
        let replacementRequest = PackageCreationRequest(
            title: "Replacement",
            packageVersion: "1",
            author: "",
            summary: "",
            inputURLs: [input.appendingPathComponent("hello.txt")],
            iconURL: nil,
            fallbackIconURL: icon,
            encryptionEnabled: false,
            password: "",
            destinationURL: replacementArchive
        )
        _ = try PackageBuilder.create(replacementRequest)
        try Data(contentsOf: replacementArchive).write(to: plainArchive, options: .atomic)
        do {
            _ = try PackageBuilder.extract(plainInfo, to: extractParent)
            throw TestError("A package replaced after review was extracted.")
        } catch PackageBuilderError.archiveChanged {
            // Expected: extraction is bound to the bytes the user reviewed.
        }

        print("PASS: encryption + ZIP integrity + bounded thumbnails/metadata + review-bound extraction + nested symlink and portable-path rejection")
        print("FILES: \(reopened.payloadFiles.map(\.path).joined(separator: ", "))")
    }

}
