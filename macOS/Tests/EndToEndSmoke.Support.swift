import Foundation

extension EndToEndSmoke {
    static func replaceAll(in data: inout Data, source: Data, replacement: Data) -> Int {
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

    static func patchUncompressedSize(
        in archive: URL,
        entryPath: String,
        replacement: UInt32
    ) throws {
        var data = try Data(contentsOf: archive)
        let name = Data(entryPath.utf8)
        var searchStart = data.startIndex
        var patched = 0
        while searchStart < data.endIndex,
              let range = data.range(of: name, in: searchStart..<data.endIndex) {
            if range.lowerBound >= 30,
               readUInt32LE(data, at: range.lowerBound - 30) == 0x0403_4b50 {
                writeUInt32LE(replacement, to: &data, at: range.lowerBound - 30 + 22)
                patched += 1
            } else if range.lowerBound >= 46,
                      readUInt32LE(data, at: range.lowerBound - 46) == 0x0201_4b50 {
                writeUInt32LE(replacement, to: &data, at: range.lowerBound - 46 + 24)
                patched += 1
            }
            searchStart = range.upperBound
        }
        try require(patched == 2, "The dishonest-size ZIP fixture could not be patched.")
        try data.write(to: archive, options: .atomic)
    }

    static func createManifestMismatchArchive(
        from source: URL,
        to destination: URL,
        stagingAt staging: URL
    ) throws {
        try createModifiedArchive(from: source, to: destination, stagingAt: staging) { staging in
            let manifestURL = staging.appendingPathComponent("manifest.json")
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let original = try decoder.decode(BundlePackManifest.self, from: Data(contentsOf: manifestURL))
            let mismatched = BundlePackManifest(
                title: original.title,
                packageVersion: original.packageVersion,
                author: original.author,
                summary: original.summary,
                createdAt: original.createdAt,
                files: []
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(mismatched).write(to: manifestURL, options: .atomic)
        }
    }

    static func createModifiedArchive(
        from source: URL,
        to destination: URL,
        stagingAt staging: URL,
        modify: (URL) throws -> Void
    ) throws {
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try run(
            executable: "/usr/bin/unzip",
            arguments: ["-qq", source.path, "-d", staging.path],
            currentDirectory: nil
        )
        try modify(staging)

        try run(
            executable: "/usr/bin/zip",
            arguments: ["-0", "-X", "-q", destination.path, "icon.png", "manifest.json"],
            currentDirectory: staging
        )
        try run(
            executable: "/usr/bin/zip",
            arguments: ["-r", "-X", "-q", destination.path, "payload"],
            currentDirectory: staging
        )
    }

    static func run(executable: String, arguments: [String], currentDirectory: URL?) throws {
        let process = Process()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = standardError
        try process.run()
        var errorData = Data()
        while let chunk = try? standardError.fileHandleForReading.read(upToCount: 8_192),
              !chunk.isEmpty {
            if errorData.count < 65_536 {
                errorData.append(chunk.prefix(65_536 - errorData.count))
            }
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? "Exit code \(process.terminationStatus)"
            throw TestError(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    static func requireDuplicatePathRejected(_ archive: URL) throws {
        do {
            _ = try ZipArchiveInspector.inspect(archive)
            throw TestError("An archive with colliding output paths was not rejected.")
        } catch BundlePackArchiveError.duplicateEntry {
            // Expected: untrusted archives must not contain colliding output paths.
        }
    }

    static func requireUnsafePathRejected(_ archive: URL) throws {
        do {
            _ = try ZipArchiveInspector.inspect(archive)
            throw TestError("An archive with a normalized dot path was not rejected.")
        } catch BundlePackArchiveError.unsafeEntry {
            // Expected: extraction must never normalize an entry onto another output path.
        }
    }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw TestError(message) }
    }

    struct TestError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    final class ProgressRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storedValues: [Double] = []

        var values: [Double] {
            lock.lock()
            defer { lock.unlock() }
            return storedValues
        }

        func record(_ value: Double) {
            lock.lock()
            storedValues.append(value)
            lock.unlock()
        }
    }

    private static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func writeUInt32LE(_ value: UInt32, to data: inout Data, at offset: Int) {
        data[offset] = UInt8(truncatingIfNeeded: value)
        data[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
        data[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
        data[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
    }
}
