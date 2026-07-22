import Foundation

@main
enum CompatibilitySmoke {
    private static let password = "BundlePack-Compatibility-2026!"
    private static let composedUnicodePassword = "Caf\u{e9}-Compatibility-2026!"
    private static let decomposedUnicodePassword = "Cafe\u{301}-Compatibility-2026!"

    static func main() throws {
        guard CommandLine.arguments.count >= 2 else {
            throw TestError("At least one fixture directory is required.")
        }

        for directoryPath in CommandLine.arguments.dropFirst() {
            let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
            let prefixes = ["macos", "windows"]
            var verified = false
            for prefix in prefixes {
                let unencrypted = directory.appendingPathComponent("\(prefix)-unencrypted.bundlepack")
                let encrypted = directory.appendingPathComponent("\(prefix)-encrypted.bundlepack")
                let unicodePassword = directory.appendingPathComponent("\(prefix)-unicode-password.bundlepack")
                guard FileManager.default.fileExists(atPath: unencrypted.path)
                    || FileManager.default.fileExists(atPath: encrypted.path)
                    || FileManager.default.fileExists(atPath: unicodePassword.path) else {
                    continue
                }
                guard FileManager.default.fileExists(atPath: unencrypted.path),
                      FileManager.default.fileExists(atPath: encrypted.path),
                      FileManager.default.fileExists(atPath: unicodePassword.path) else {
                    throw TestError("The \(prefix) fixture set is incomplete in \(directory.path).")
                }

                try verifyUnencrypted(unencrypted)
                try verifyEncrypted(encrypted, password: password)
                try verifyEncrypted(
                    unicodePassword,
                    password: prefix == "macos" ? composedUnicodePassword : decomposedUnicodePassword
                )
                verified = true
            }

            guard verified else {
                throw TestError("No compatibility fixture set was found in \(directory.path).")
            }
        }

        print("PASS: macOS opened all macOS and Windows fixtures, including NFC-equivalent passwords")
    }

    private static func verifyUnencrypted(_ url: URL) throws {
        let info = try ZipArchiveInspector.inspect(url)
        try verifyPayload(info)
    }

    private static func verifyEncrypted(_ url: URL, password: String) throws {
        let publicInfo = try BundlePackEncryptedContainer.readPublicInfo(from: url)
        let decrypted = FileManager.default.temporaryDirectory
            .appendingPathComponent("BundlePack-Compatibility-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: decrypted) }
        try BundlePackEncryptedContainer.open(url, password: password, to: decrypted)
        let info = try ZipArchiveInspector.inspect(decrypted)
        guard publicInfo.iconData == info.iconData else {
            throw TestError("The encrypted fixture's public and private icons differ.")
        }
        try verifyPayload(info)
    }

    private static func verifyPayload(_ info: BundlePackArchiveInfo) throws {
        let paths = Set(info.payloadFiles.map(\.path))
        guard paths.contains("hello.txt"), paths.contains("nested/data.bin") else {
            throw TestError("The compatibility payload is incomplete: \(paths.sorted())")
        }
    }

    private struct TestError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
