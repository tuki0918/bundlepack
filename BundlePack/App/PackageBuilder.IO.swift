import AppKit
import Foundation
import ImageIO

extension PackageBuilder {
    private static let maximumIconSourceBytes = 32 * 1_024 * 1_024
    private static let maximumIconSourceDimension = 16_384.0
    private static let maximumIconSourcePixels = 100_000_000.0
    private static let maximumTotalInputBytes: UInt64 = 20 * 1_024 * 1_024 * 1_024

    static func validateInput(_ url: URL) throws {
        try Task.checkCancellation()
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isDirectoryKey, .fileSizeKey]
        try validatePortableFilename(url.lastPathComponent)
        let values = try url.resourceValues(forKeys: keys)
        if values.isSymbolicLink == true {
            throw PackageBuilderError.symbolicLink(url.path)
        }
        if let size = values.fileSize, UInt64(size) >= UInt64(UInt32.max) {
            throw PackageBuilderError.fileTooLarge(url.path)
        }
        guard values.isDirectory == true else { return }

        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw PackageBuilderError.unreadableInput(url.path)
        }

        for case let child as URL in enumerator {
            try Task.checkCancellation()
            try validatePortableFilename(child.lastPathComponent)
            let childValues = try child.resourceValues(forKeys: keys)
            if childValues.isSymbolicLink == true {
                throw PackageBuilderError.symbolicLink(child.path)
            }
            if let size = childValues.fileSize, UInt64(size) >= UInt64(UInt32.max) {
                throw PackageBuilderError.fileTooLarge(child.path)
            }
        }
        if enumerationError != nil {
            throw PackageBuilderError.unreadableInput(url.path)
        }
    }

    static func installUnencryptedArchive(
        _ archive: URL,
        at destination: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws {
        let fileManager = FileManager.default
        let destinationDirectory = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let temporary = destinationDirectory.appendingPathComponent(
            ".\(destination.lastPathComponent).\(UUID().uuidString).tmp"
        )
        defer { try? fileManager.removeItem(at: temporary) }

        // Copy first so the completed temporary file is always on the same
        // volume as the final destination. This also supports external drives.
        let archiveSize = UInt64(try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        var copiedBytes: UInt64 = 0
        try copyFile(from: archive, to: temporary, copiedBytes: &copiedBytes) { currentBytes in
            progress?(archiveSize == 0 ? 1 : Double(currentBytes) / Double(archiveSize))
        }
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
    }

    static func inputByteCount(_ urls: [URL]) throws -> UInt64 {
        var total: UInt64 = 0
        for url in urls {
            total = try checkedByteSum(total, inputByteCount(url), path: url.path)
            guard total <= maximumTotalInputBytes else {
                throw PackageBuilderError.packageTooLarge
            }
        }
        return total
    }

    private static func inputByteCount(_ url: URL) throws -> UInt64 {
        try Task.checkCancellation()
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
        if values.isSymbolicLink == true {
            throw PackageBuilderError.symbolicLink(url.path)
        }
        guard values.isDirectory == true else {
            let size = UInt64(values.fileSize ?? 0)
            guard size < UInt64(UInt32.max) else {
                throw PackageBuilderError.fileTooLarge(url.path)
            }
            return size
        }

        var total: UInt64 = 0
        for child in try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: []
        ) {
            total = try checkedByteSum(total, inputByteCount(child), path: child.path)
        }
        return total
    }

    static func copyInput(
        from source: URL,
        to destination: URL,
        copiedBytes: inout UInt64,
        didCopy: @Sendable (UInt64) -> Void
    ) throws {
        try Task.checkCancellation()
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        if values.isSymbolicLink == true {
            throw PackageBuilderError.symbolicLink(source.path)
        }
        if values.isDirectory == true {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let children = try FileManager.default.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: nil,
                options: []
            ).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            for child in children {
                try copyInput(
                    from: child,
                    to: destination.appendingPathComponent(child.lastPathComponent),
                    copiedBytes: &copiedBytes,
                    didCopy: didCopy
                )
            }
            return
        }
        try copyFile(from: source, to: destination, copiedBytes: &copiedBytes, didCopy: didCopy)
    }

    static func copyFile(
        from source: URL,
        to destination: URL,
        copiedBytes: inout UInt64,
        didCopy: @Sendable (UInt64) -> Void
    ) throws {
        try Task.checkCancellation()
        let expectedSize = UInt64(try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        guard expectedSize < UInt64(UInt32.max) else {
            throw PackageBuilderError.fileTooLarge(source.path)
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw PackageBuilderError.unreadableInput(source.path)
        }
        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: destination)
        defer {
            try? input.close()
            try? output.close()
        }
        var fileBytes: UInt64 = 0
        while let chunk = try input.read(upToCount: 1_024 * 1_024), !chunk.isEmpty {
            try Task.checkCancellation()
            fileBytes = try checkedByteSum(fileBytes, UInt64(chunk.count), path: source.path)
            guard fileBytes <= expectedSize else {
                throw PackageBuilderError.fileTooLarge(source.path)
            }
            try output.write(contentsOf: chunk)
            copiedBytes = try checkedByteSum(copiedBytes, UInt64(chunk.count), path: source.path)
            didCopy(copiedBytes)
        }
        guard fileBytes == expectedSize else {
            throw PackageBuilderError.unreadableInput(source.path)
        }
        try output.synchronize()
        if expectedSize == 0 { didCopy(copiedBytes) }
    }

    private static func checkedByteSum(_ lhs: UInt64, _ rhs: UInt64, path: String) throws -> UInt64 {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else { throw PackageBuilderError.fileTooLarge(path) }
        return result
    }

    private static func validatePortableFilename(_ name: String) throws {
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
        guard !name.isEmpty,
              !name.hasSuffix(" "),
              !name.hasSuffix("."),
              name.rangeOfCharacter(from: forbidden) == nil,
              !reserved.contains(stem) else {
            throw PackageBuilderError.unsupportedFilename(name)
        }
    }

    static func payloadFiles(at payload: URL) throws -> [BundlePackFile] {
        let fileManager = FileManager.default
        let resolvedPayload = payload.resolvingSymlinksInPath().standardizedFileURL
        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: resolvedPayload,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw PackageBuilderError.unreadableInput(payload.path)
        }

        var result: [BundlePackFile] = []
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
            let prefix = resolvedPayload.path + "/"
            guard resolvedURL.path.hasPrefix(prefix) else {
                throw PackageBuilderError.unsupportedFilename(url.lastPathComponent)
            }
            let relative = String(resolvedURL.path.dropFirst(prefix.count))
            result.append(BundlePackFile(path: relative, size: UInt64(values.fileSize ?? 0)))
        }
        if enumerationError != nil {
            throw PackageBuilderError.unreadableInput(payload.path)
        }
        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    static func normalizedPNG(from url: URL) throws -> Data {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let sourceBytes = values.fileSize,
              sourceBytes > 0,
              sourceBytes <= maximumIconSourceBytes else {
            throw PackageBuilderError.invalidIcon
        }
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
           let height = properties[kCGImagePropertyPixelHeight] as? NSNumber {
            let pixelWidth = width.doubleValue
            let pixelHeight = height.doubleValue
            guard pixelWidth > 0,
                  pixelHeight > 0,
                  pixelWidth <= maximumIconSourceDimension,
                  pixelHeight <= maximumIconSourceDimension,
                  pixelWidth * pixelHeight <= maximumIconSourcePixels else {
                throw PackageBuilderError.invalidIcon
            }
        }
        guard let image = NSImage(contentsOf: url) else { throw PackageBuilderError.invalidIcon }
        let sourceSize = image.size
        guard sourceSize.width > 0,
              sourceSize.height > 0,
              sourceSize.width <= maximumIconSourceDimension,
              sourceSize.height <= maximumIconSourceDimension,
              sourceSize.width * sourceSize.height <= maximumIconSourcePixels else {
            throw PackageBuilderError.invalidIcon
        }

        let target = NSSize(width: 1_024, height: 1_024)
        guard let output = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(target.width),
            pixelsHigh: Int(target.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: output) else {
            throw PackageBuilderError.invalidIcon
        }

        // Draw into an explicitly sized bitmap. NSImage.lockFocus() uses the
        // active display's backing scale and can otherwise produce a 2048 px
        // image on Retina Macs even though the requested point size is 1024.
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        context.cgContext.clear(NSRect(origin: .zero, size: target))
        context.imageInterpolation = .high
        let scale = min(target.width / sourceSize.width, target.height / sourceSize.height)
        let size = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let rect = NSRect(
            x: (target.width - size.width) / 2,
            y: (target.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        context.flushGraphics()

        guard let png = output.representation(using: .png, properties: [.compressionFactor: 0.85]) else {
            throw PackageBuilderError.invalidIcon
        }
        return png
    }

    static func run(executable: String, arguments: [String], currentDirectory: URL?) throws {
        try Task.checkCancellation()
        let process = Process()
        let errorURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BundlePack-Process-\(UUID().uuidString).log")
        guard FileManager.default.createFile(atPath: errorURL.path, contents: nil) else {
            throw PackageBuilderError.commandFailed("The process log could not be created.")
        }
        defer { try? FileManager.default.removeItem(at: errorURL) }
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer { try? errorHandle.close() }
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardError = errorHandle
        process.standardOutput = FileHandle.nullDevice

        try process.run()
        while process.isRunning {
            if Task.isCancelled {
                process.terminate()
                process.waitUntilExit()
                throw CancellationError()
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        try errorHandle.synchronize()
        let errorData = (try? Data(contentsOf: errorURL).prefix(65_536)) ?? Data()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? "Exit code \(process.terminationStatus)"
            throw PackageBuilderError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    static func uniqueName(for original: String, usedNames: inout Set<String>) -> String {
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

    static func safeFilename(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)
        let components = value.components(separatedBy: forbidden).filter { !$0.isEmpty }
        let result = components.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty || result == "." || result == ".." ? "BundlePack" : result
    }

    static func uniqueDestination(_ original: URL, fileManager: FileManager) -> URL {
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
