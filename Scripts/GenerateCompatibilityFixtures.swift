import AppKit
import Foundation

@main
enum GenerateCompatibilityFixtures {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw FixtureError("Usage: generator <output-directory>")
        }

        let fileManager = FileManager.default
        let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("BundlePack-Compatibility-\(UUID().uuidString)", isDirectory: true)
        let icon = temporaryRoot.appendingPathComponent("fixture-icon.png")
        let nested = temporaryRoot.appendingPathComponent("nested", isDirectory: true)
        let hello = temporaryRoot.appendingPathComponent("hello.txt")
        let data = nested.appendingPathComponent("data.bin")
        let password = "BundlePack-Compatibility-2026!"
        let decomposedUnicodePassword = "Cafe\u{301}-Compatibility-2026!"

        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
        try makeFixtureIcon().write(to: icon)
        try Data("Hello from BundlePack compatibility tests\n".utf8).write(to: hello)
        try Data([0, 1, 2, 3, 4, 5]).write(to: data)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        let inputs = [hello, nested]
        let common = (
            title: "macOS Compatibility",
            version: "1.0.0",
            author: "BundlePack Tests",
            summary: "Created by the Swift compatibility fixture generator."
        )

        _ = try PackageBuilder.create(
            PackageCreationRequest(
                title: common.title,
                packageVersion: common.version,
                author: common.author,
                summary: common.summary,
                inputURLs: inputs,
                iconURL: nil,
                fallbackIconURL: icon,
                encryptionEnabled: false,
                password: "",
                destinationURL: outputDirectory.appendingPathComponent("macos-unencrypted.bundlepack")
            )
        )

        _ = try PackageBuilder.create(
            PackageCreationRequest(
                title: common.title,
                packageVersion: common.version,
                author: common.author,
                summary: common.summary,
                inputURLs: inputs,
                iconURL: nil,
                fallbackIconURL: icon,
                encryptionEnabled: true,
                password: password,
                destinationURL: outputDirectory.appendingPathComponent("macos-encrypted.bundlepack")
            )
        )

        _ = try PackageBuilder.create(
            PackageCreationRequest(
                title: "macOS Unicode Password Compatibility",
                packageVersion: common.version,
                author: common.author,
                summary: "Created with a canonically decomposed Unicode password.",
                inputURLs: inputs,
                iconURL: nil,
                fallbackIconURL: icon,
                encryptionEnabled: true,
                password: decomposedUnicodePassword,
                destinationURL: outputDirectory.appendingPathComponent("macos-unicode-password.bundlepack")
            )
        )

        print("Generated macOS compatibility fixtures in \(outputDirectory.path)")
    }

    private static func makeFixtureIcon() throws -> Data {
        let size = NSSize(width: 1_024, height: 1_024)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedRed: 0.12, green: 0.48, blue: 0.88, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [.compressionFactor: 1]) else {
            throw FixtureError("The fixture icon could not be generated.")
        }
        return png
    }

    private struct FixtureError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
