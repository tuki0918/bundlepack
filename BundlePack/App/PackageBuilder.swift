import AppKit
import Foundation

enum PackageBuilderError: LocalizedError {
    case noInputFiles
    case invalidIcon
    case symbolicLink(String)
    case fileTooLarge(String)
    case commandFailed(String)
    case missingPayload

    var errorDescription: String? {
        switch self {
        case .noInputFiles:
            return "Choose at least one file or folder to include."
        case .invalidIcon:
            return "The selected image could not be converted to PNG."
        case .symbolicLink(let path):
            return "Symbolic links cannot be included in a shared package: \(path)"
        case .fileTooLarge(let path):
            return "This prototype cannot include files that are 4 GB or larger: \(path)"
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
    static func create(_ request: PackageCreationRequest) throws -> CreatedBundlePack {
        guard !request.inputURLs.isEmpty else { throw PackageBuilderError.noInputFiles }

        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("BundlePack-\(UUID().uuidString)", isDirectory: true)
        let staging = temporaryRoot.appendingPathComponent("staging", isDirectory: true)
        let payload = staging.appendingPathComponent("payload", isDirectory: true)
        let archive = temporaryRoot.appendingPathComponent("archive.zip")

        try fileManager.createDirectory(at: payload, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        var usedNames = Set<String>()
        for inputURL in request.inputURLs {
            try validateInput(inputURL)
            let name = uniqueName(for: inputURL.lastPathComponent, usedNames: &usedNames)
            try fileManager.copyItem(at: inputURL, to: payload.appendingPathComponent(name))
        }

        let files = try payloadFiles(at: payload)
        let manifest = BundlePackManifest(
            title: request.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Untitled Package"
                : request.title.trimmingCharacters(in: .whitespacesAndNewlines),
            packageVersion: request.packageVersion.trimmingCharacters(in: .whitespacesAndNewlines),
            author: request.author.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: request.summary.trimmingCharacters(in: .whitespacesAndNewlines),
            files: files
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(
            to: staging.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )

        let iconSource = request.iconURL ?? request.fallbackIconURL
        let iconData = try normalizedPNG(from: iconSource)
        try iconData.write(to: staging.appendingPathComponent("icon.png"), options: [.atomic])

        try run(
            executable: "/usr/bin/zip",
            arguments: ["-0", "-X", "-q", archive.path, "icon.png", "manifest.json"],
            currentDirectory: staging
        )
        try run(
            executable: "/usr/bin/zip",
            arguments: ["-r", "-X", "-q", archive.path, "payload"],
            currentDirectory: staging
        )

        if request.encryptionEnabled {
            return .encrypted(
                try BundlePackEncryptedContainer.seal(
                    archive: archive,
                    iconData: iconData,
                    password: request.password,
                    to: request.destinationURL
                )
            )
        }

        if fileManager.fileExists(atPath: request.destinationURL.path) {
            try fileManager.removeItem(at: request.destinationURL)
        }
        try fileManager.moveItem(at: archive, to: request.destinationURL)
        return .unencrypted(try ZipArchiveInspector.inspect(request.destinationURL))
    }

    static func extract(_ archiveURL: URL, to parentDirectory: URL) throws -> URL {
        let info = try ZipArchiveInspector.inspect(archiveURL)
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("BundlePack-Extract-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        try run(
            executable: "/usr/bin/unzip",
            arguments: ["-qq", archiveURL.path, "-d", temporaryRoot.path],
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

        for item in try fileManager.contentsOfDirectory(
            at: payload,
            includingPropertiesForKeys: nil,
            options: []
        ) {
            try fileManager.moveItem(
                at: item,
                to: destination.appendingPathComponent(item.lastPathComponent)
            )
        }
        return destination
    }

    private static func validateInput(_ url: URL) throws {
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isDirectoryKey, .fileSizeKey]
        let values = try url.resourceValues(forKeys: keys)
        if values.isSymbolicLink == true {
            throw PackageBuilderError.symbolicLink(url.path)
        }
        if let size = values.fileSize, UInt64(size) >= UInt64(UInt32.max) {
            throw PackageBuilderError.fileTooLarge(url.path)
        }
        guard values.isDirectory == true else { return }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in false }
        ) else { return }

        for case let child as URL in enumerator {
            let childValues = try child.resourceValues(forKeys: keys)
            if childValues.isSymbolicLink == true {
                throw PackageBuilderError.symbolicLink(child.path)
            }
            if let size = childValues.fileSize, UInt64(size) >= UInt64(UInt32.max) {
                throw PackageBuilderError.fileTooLarge(child.path)
            }
        }
    }

    private static func payloadFiles(at payload: URL) throws -> [BundlePackFile] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: payload,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [],
            errorHandler: { _, _ in false }
        ) else { return [] }

        var result: [BundlePackFile] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            let relative = String(url.path.dropFirst(payload.path.count + 1))
            result.append(BundlePackFile(path: relative, size: UInt64(values.fileSize ?? 0)))
        }
        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private static func normalizedPNG(from url: URL) throws -> Data {
        guard let image = NSImage(contentsOf: url) else { throw PackageBuilderError.invalidIcon }
        let target = NSSize(width: 1_024, height: 1_024)
        let output = NSImage(size: target)
        output.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: target).fill()

        let sourceSize = image.size
        let scale = min(target.width / sourceSize.width, target.height / sourceSize.height)
        let size = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let rect = NSRect(
            x: (target.width - size.width) / 2,
            y: (target.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        output.unlockFocus()

        guard let tiff = output.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [.compressionFactor: 0.85]) else {
            throw PackageBuilderError.invalidIcon
        }
        return png
    }

    private static func run(executable: String, arguments: [String], currentDirectory: URL?) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardError = errorPipe
        process.standardOutput = Pipe()

        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "Exit code \(process.terminationStatus)"
            throw PackageBuilderError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func uniqueName(for original: String, usedNames: inout Set<String>) -> String {
        let originalKey = outputNameKey(original)
        guard usedNames.contains(originalKey) else {
            usedNames.insert(originalKey)
            return original
        }
        let source = original as NSString
        let base = source.deletingPathExtension
        let ext = source.pathExtension
        var index = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            let candidateKey = outputNameKey(candidate)
            if !usedNames.contains(candidateKey) {
                usedNames.insert(candidateKey)
                return candidate
            }
            index += 1
        }
    }

    private static func outputNameKey(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func safeFilename(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\")
        let components = value.components(separatedBy: forbidden).filter { !$0.isEmpty }
        let result = components.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "BundlePack" : result
    }

    private static func uniqueDestination(_ original: URL, fileManager: FileManager) -> URL {
        guard fileManager.fileExists(atPath: original.path) else { return original }
        var index = 2
        while true {
            let candidate = original.deletingLastPathComponent()
                .appendingPathComponent("\(original.lastPathComponent) \(index)", isDirectory: true)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }
}
