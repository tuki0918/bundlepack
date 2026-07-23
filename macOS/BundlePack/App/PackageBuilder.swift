import Foundation

enum PackageBuilderError: LocalizedError {
    case noInputFiles
    case invalidIcon
    case invalidAnimation
    case symbolicLink(String)
    case unsupportedFilename(String)
    case fileTooLarge(String)
    case packageTooLarge
    case unreadableInput(String)
    case invalidMetadata
    case archiveChanged
    case commandFailed(String)
    case missingPayload

    var errorDescription: String? {
        switch self {
        case .noInputFiles:
            return "Choose at least one file or folder to include."
        case .invalidIcon:
            return "The selected image could not be converted to PNG."
        case .invalidAnimation:
            return "The selected GIF must contain 2–120 frames, use a canvas no larger than 1024 × 1024, and be 16 MB or smaller."
        case .symbolicLink(let path):
            return "Symbolic links cannot be included in a shared package: \(path)"
        case .unsupportedFilename(let name):
            return "This file name is not portable between macOS and Windows: \(name)"
        case .fileTooLarge(let path):
            return "BundlePack cannot include files that are 4 GB or larger: \(path)"
        case .packageTooLarge:
            return "The package exceeds the 20 GB expanded-size limit."
        case .unreadableInput(let path):
            return "BundlePack could not read every item in: \(path)"
        case .invalidMetadata:
            return "Package metadata is too long or contains unsupported control characters."
        case .archiveChanged:
            return "The package changed after it was opened. Open it again before extracting."
        case .commandFailed(let message):
            return "The ZIP could not be created or extracted.\n\(message)"
        case .missingPayload:
            return "The payload folder is missing."
        }
    }
}
struct PackageCreationRequest: Sendable {
    let title: String
    let packageVersion: String
    let author: String
    let summary: String
    let inputURLs: [URL]
    let iconURL: URL?
    let fallbackIconURL: URL
    let encryptionEnabled: Bool
    let password: String
    let destinationURL: URL
}

enum CreatedBundlePack: Sendable {
    case encrypted(EncryptedBundlePackInfo)
    case unencrypted(BundlePackArchiveInfo)
}

enum PackageBuilder {
    static func create(
        _ request: PackageCreationRequest,
        progress: BundlePackProgressHandler? = nil
    ) throws -> CreatedBundlePack {
        try Task.checkCancellation()
        guard !request.inputURLs.isEmpty else { throw PackageBuilderError.noInputFiles }
        progress?(BundlePackOperationProgress(fractionCompleted: 0, message: "Preparing files…"))

        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("BundlePack-\(UUID().uuidString)", isDirectory: true)
        let staging = temporaryRoot.appendingPathComponent("staging", isDirectory: true)
        let payload = staging.appendingPathComponent("payload", isDirectory: true)
        let archive = temporaryRoot.appendingPathComponent("archive.zip")

        try fileManager.createDirectory(at: payload, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        for inputURL in request.inputURLs {
            try Task.checkCancellation()
            try validateInput(inputURL)
        }
        let totalInputBytes = try inputByteCount(request.inputURLs)
        var copiedInputBytes: UInt64 = 0
        var usedNames = Set<String>()
        for inputURL in request.inputURLs {
            try Task.checkCancellation()
            let name = uniqueName(for: inputURL.lastPathComponent, usedNames: &usedNames)
            try copyInput(
                from: inputURL,
                to: payload.appendingPathComponent(name),
                copiedBytes: &copiedInputBytes
            ) { copiedBytes in
                let localFraction = totalInputBytes == 0
                    ? 1
                    : Double(copiedBytes) / Double(totalInputBytes)
                progress?(BundlePackOperationProgress(
                    fractionCompleted: 0.05 + localFraction * 0.4,
                    message: "Copying files…"
                ))
            }
        }
        progress?(BundlePackOperationProgress(fractionCompleted: 0.45, message: "Preparing package metadata…"))
        // Re-check the private staging tree to close source check/copy races and
        // to ensure no copied package descendant contains a symbolic link.
        try validateInput(payload)

        let files = try payloadFiles(at: payload)
        let normalizedTitle = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedVersion = request.packageVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAuthor = request.author.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSummary = request.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let manifestTitle = normalizedTitle.isEmpty ? "Untitled Package" : normalizedTitle
        guard BundlePackManifest.hasValidDisplayMetadata(
            title: manifestTitle,
            packageVersion: normalizedVersion,
            author: normalizedAuthor,
            summary: normalizedSummary
        ) else {
            throw PackageBuilderError.invalidMetadata
        }
        let iconSource = request.iconURL ?? request.fallbackIconURL
        let animationData = try validatedAnimationGIF(from: request.iconURL)
        let iconData = try normalizedPNG(from: iconSource)
        let manifest = BundlePackManifest(
            title: manifestTitle,
            packageVersion: normalizedVersion,
            author: normalizedAuthor,
            summary: normalizedSummary,
            files: files,
            animation: animationData == nil ? nil : .gif
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(
            to: staging.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )

        try iconData.write(to: staging.appendingPathComponent("icon.png"), options: [.atomic])
        if let animationData {
            try animationData.write(
                to: staging.appendingPathComponent(BundlePackAnimationValidator.path),
                options: [.atomic]
            )
        }

        progress?(BundlePackOperationProgress(fractionCompleted: 0.52, message: "Compressing files…"))
        try run(
            executable: "/usr/bin/zip",
            arguments: ["-0", "-X", "-q", archive.path, "icon.png", "manifest.json"],
            currentDirectory: staging
        )
        if animationData != nil {
            try run(
                executable: "/usr/bin/zip",
                arguments: ["-0", "-X", "-q", archive.path, BundlePackAnimationValidator.path],
                currentDirectory: staging
            )
        }
        try run(
            executable: "/usr/bin/zip",
            arguments: ["-r", "-y", "-X", "-q", archive.path, "payload"],
            currentDirectory: staging
        )

        // Apply all reader-side structural and metadata checks to the completed
        // inner archive before it is moved or encrypted.
        progress?(BundlePackOperationProgress(fractionCompleted: 0.72, message: "Validating package…"))
        _ = try ZipArchiveInspector.inspect(archive)

        if request.encryptionEnabled {
            let encrypted = try BundlePackEncryptedContainer.seal(
                archive: archive,
                iconData: iconData,
                password: request.password,
                to: request.destinationURL,
                progress: { value in
                    progress?(BundlePackOperationProgress(
                        fractionCompleted: 0.78 + value.fractionCompleted * 0.21,
                        message: value.message
                    ))
                }
            )
            progress?(BundlePackOperationProgress(fractionCompleted: 1, message: "Package created"))
            return .encrypted(encrypted)
        }

        try installUnencryptedArchive(archive, at: request.destinationURL) { value in
            progress?(BundlePackOperationProgress(
                fractionCompleted: 0.78 + value * 0.21,
                message: "Writing package…"
            ))
        }
        progress?(BundlePackOperationProgress(fractionCompleted: 1, message: "Package created"))
        return .unencrypted(try ZipArchiveInspector.inspect(request.destinationURL))
    }

    static func extract(
        _ archiveURL: URL,
        to parentDirectory: URL,
        progress: BundlePackProgressHandler? = nil
    ) throws -> URL {
        try extract(ZipArchiveInspector.inspect(archiveURL), to: parentDirectory, progress: progress)
    }

    static func extract(
        _ expectedInfo: BundlePackArchiveInfo,
        to parentDirectory: URL,
        progress: BundlePackProgressHandler? = nil
    ) throws -> URL {
        try Task.checkCancellation()
        progress?(BundlePackOperationProgress(fractionCompleted: 0, message: "Preparing extraction…"))
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("BundlePack-Extract-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        let snapshot = temporaryRoot.appendingPathComponent("archive.bundlepack")
        var copiedBytes: UInt64 = 0
        try copyFile(from: expectedInfo.url, to: snapshot, copiedBytes: &copiedBytes) { currentBytes in
            let fraction = expectedInfo.archiveSize == 0
                ? 1
                : Double(currentBytes) / Double(expectedInfo.archiveSize)
            progress?(BundlePackOperationProgress(
                fractionCompleted: fraction * 0.12,
                message: "Creating a safe snapshot…"
            ))
        }
        let info = try ZipArchiveInspector.inspect(
            snapshot,
            validatePayloads: true,
            progress: { value in
                progress?(BundlePackOperationProgress(
                    fractionCompleted: 0.12 + value.fractionCompleted * 0.63,
                    message: "Validating contents…"
                ))
            }
        )
        guard info.archiveDigest == expectedInfo.archiveDigest else {
            throw PackageBuilderError.archiveChanged
        }

        // Payload streams were expanded into a bounded in-memory buffer and
        // checked against their declared sizes and CRCs by the inspector.
        progress?(BundlePackOperationProgress(fractionCompleted: 0.78, message: "Extracting files…"))
        try run(
            executable: "/usr/bin/unzip",
            arguments: ["-qq", snapshot.path, "-d", temporaryRoot.path],
            currentDirectory: nil
        )

        let payload = temporaryRoot.appendingPathComponent("payload", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: payload.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PackageBuilderError.missingPayload
        }

        let safeTitle = safeFilename(info.manifest.title)
        let destination = uniqueDestination(
            parentDirectory.appendingPathComponent(safeTitle, isDirectory: true),
            fileManager: fileManager
        )
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        let totalPayloadBytes = info.payloadFiles.reduce(UInt64(0)) { $0 + $1.size }
        var installedBytes: UInt64 = 0
        do {
            for item in try fileManager.contentsOfDirectory(
                at: payload,
                includingPropertiesForKeys: nil,
                options: []
            ) {
                try Task.checkCancellation()
                try copyInput(
                    from: item,
                    to: destination.appendingPathComponent(item.lastPathComponent),
                    copiedBytes: &installedBytes
                ) { copiedBytes in
                    let localFraction = totalPayloadBytes == 0
                        ? 1
                        : Double(copiedBytes) / Double(totalPayloadBytes)
                    progress?(BundlePackOperationProgress(
                        fractionCompleted: 0.82 + localFraction * 0.18,
                        message: "Installing extracted files…"
                    ))
                }
            }
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
        progress?(BundlePackOperationProgress(fractionCompleted: 1, message: "Extraction complete"))
        return destination
    }
}
