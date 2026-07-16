import AppKit
import Foundation

@main
enum EndToEndSmoke {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw TestError("A path to DefaultPackageIcon.png is required.")
        }

        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("BundlePack-Smoke-\(UUID().uuidString)", isDirectory: true)
        let input = root.appendingPathComponent("input", isDirectory: true)
        let nested = input.appendingPathComponent("nested", isDirectory: true)
        let archive = root.appendingPathComponent("Demo.bundlepack")
        let plainArchive = root.appendingPathComponent("Plain.bundlepack")
        let extractParent = root.appendingPathComponent("extracted", isDirectory: true)
        let decryptedArchive = root.appendingPathComponent("decrypted.zip")
        let icon = URL(fileURLWithPath: CommandLine.arguments[1])
        let password = "Correct-Horse-Battery-2026!"

        try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: extractParent, withIntermediateDirectories: true)
        try Data("Hello BundlePack\n".utf8).write(to: input.appendingPathComponent("hello.txt"))
        try Data([0, 1, 2, 3, 4, 5]).write(to: nested.appendingPathComponent("data.bin"))
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

        let created = try PackageBuilder.create(request)
        guard case .encrypted(let encryptedInfo) = created else {
            throw TestError("The encrypted package was not created in the encrypted format.")
        }
        try require(encryptedInfo.originalArchiveSize > 0, "The original archive size is missing.")

        let encryptedData = try Data(contentsOf: archive, options: [.mappedIfSafe])
        try require(encryptedData.prefix(8) == Data("BPKENC01".utf8), "The encrypted container signature is missing.")
        try require(encryptedData.prefix(4) != Data([0x50, 0x4b, 0x03, 0x04]), "A ZIP signature is exposed at the outer container level.")
        try require(encryptedData.range(of: Data("hello.txt".utf8)) == nil, "A file name is exposed as plaintext.")
        try require(encryptedData.range(of: Data("Hello BundlePack".utf8)) == nil, "File content is exposed as plaintext.")

        try BundlePackEncryptedContainer.open(archive, password: password, to: decryptedArchive)
        let reopened = try ZipArchiveInspector.inspect(decryptedArchive)
        try require(reopened.manifest.title == "Demo Package", "The title does not match.")
        try require(reopened.manifest.packageVersion == "1.2.3", "The reopened version does not match.")
        try require(reopened.payloadFiles.count == 2, "The file count does not match.")
        try require(!reopened.iconData.isEmpty, "The embedded icon is missing.")
        try require(
            encryptedInfo.iconData == reopened.iconData,
            "The encrypted container's public icon does not match the package icon."
        )

        let extracted = try PackageBuilder.extract(decryptedArchive, to: extractParent)
        let extractedText = extracted
            .appendingPathComponent("input", isDirectory: true)
            .appendingPathComponent("hello.txt")
        try require(fileManager.fileExists(atPath: extractedText.path), "The extracted file is missing.")

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
        let plainResult = try PackageBuilder.create(plainRequest)
        guard case .unencrypted(let plainInfo) = plainResult else {
            throw TestError("The unencrypted package was not created in the ZIP-compatible format.")
        }
        let plainData = try Data(contentsOf: plainArchive, options: [.mappedIfSafe])
        try require(plainData.prefix(4) == Data([0x50, 0x4b, 0x03, 0x04]), "The unencrypted package is not ZIP-compatible.")
        try require(plainData.range(of: Data("hello.txt".utf8)) != nil, "The file name is missing from the unencrypted ZIP.")
        try require(plainInfo.payloadFiles.count == 2, "The unencrypted ZIP contents could not be reopened.")
        let lightweightIconData = try ZipArchiveInspector.embeddedIcon(in: plainArchive)
        try require(
            lightweightIconData == plainInfo.iconData,
            "The lightweight thumbnail icon reader returned different icon data."
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

        print("PASS: encrypted privacy + decrypt/extract + wrong-password rejection + unencrypted ZIP compatibility + safe name normalization + colliding/normalized-path rejection + symlink rejection")
        print("FILES: \(reopened.payloadFiles.map(\.path).joined(separator: ", "))")
    }

    private static func replaceAll(in data: inout Data, source: Data, replacement: Data) -> Int {
        guard !source.isEmpty, source.count == replacement.count else { return 0 }
        var count = 0
        var searchStart = data.startIndex
        while searchStart < data.endIndex,
              let range = data.range(of: source, in: searchStart..<data.endIndex) {
            data.replaceSubrange(range, with: replacement)
            count += 1
            searchStart = range.upperBound
        }
        return count
    }

    private static func requireDuplicatePathRejected(_ archive: URL) throws {
        do {
            _ = try ZipArchiveInspector.inspect(archive)
            throw TestError("An archive with colliding output paths was not rejected.")
        } catch BundlePackArchiveError.duplicateEntry {
            // Expected: untrusted archives must not contain colliding output paths.
        }
    }

    private static func requireUnsafePathRejected(_ archive: URL) throws {
        do {
            _ = try ZipArchiveInspector.inspect(archive)
            throw TestError("An archive with a normalized dot path was not rejected.")
        } catch BundlePackArchiveError.unsafeEntry {
            // Expected: extraction must never normalize an entry onto another output path.
        }
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw TestError(message) }
    }

    private struct TestError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
