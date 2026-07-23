import AppKit
import Foundation

@main
enum DragDropSmoke {
    @MainActor
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            throw TestError("A path to DefaultPackageIcon.png is required.")
        }

        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("BundlePack-Drop-Smoke-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("Folder", isDirectory: true)
        let file = root.appendingPathComponent("sample.txt")
        let archive = root.appendingPathComponent("Drop-Test.bundlepack")
        let icon = URL(fileURLWithPath: CommandLine.arguments[1])
        let animation = root.appendingPathComponent("animated-icon.gif")
        let animationData = Data(base64Encoded:
            "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAEALAAAAAABAAEAAAICRAEAIfkEAQAAAQAsAAAAAAEAAQAAAgJEAAA7"
        )!

        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("Drag and drop test\n".utf8).write(to: file)
        try animationData.write(to: animation)
        defer { try? fileManager.removeItem(at: root) }

        let request = PackageCreationRequest(
            title: "BundlePack Demo",
            packageVersion: "1.0.0",
            author: "BundlePack Test",
            summary: "Self-contained drag-and-drop smoke test",
            inputURLs: [file],
            iconURL: nil,
            fallbackIconURL: icon,
            encryptionEnabled: false,
            password: "",
            destinationURL: archive
        )
        let created = try PackageBuilder.create(request)
        guard case .unencrypted(let archiveInfo) = created else {
            throw TestError("The test package was not created in the expected format.")
        }

        let packageDataBeforeFinderIcon = try Data(contentsOf: archive)

        guard let fileProvider = NSItemProvider(contentsOf: file),
              let folderProvider = NSItemProvider(contentsOf: folder) else {
            throw TestError("The test file URL providers could not be created.")
        }

        let model = AppModel.shared
        guard model.applyFinderIcon(archiveInfo.iconData, to: archive) else {
            throw TestError("The embedded package icon could not be applied as the Finder file icon.")
        }
        let packageDataAfterFinderIcon = try Data(contentsOf: archive)
        guard packageDataBeforeFinderIcon == packageDataAfterFinderIcon else {
            throw TestError("Applying the Finder icon changed the package file contents.")
        }

        guard model.addDroppedInputItems([fileProvider, folderProvider]) else {
            throw TestError("The Create drop was not accepted.")
        }
        try await waitUntil {
            Set(model.inputURLs.map(\.standardizedFileURL)) == Set([file, folder].map(\.standardizedFileURL))
        }

        guard let iconProvider = NSItemProvider(contentsOf: icon) else {
            throw TestError("The icon file URL provider could not be created.")
        }
        guard model.useDroppedIcon([iconProvider]) else {
            throw TestError("The icon drop was not accepted.")
        }
        try await waitUntil {
            model.iconURL?.standardizedFileURL == icon.standardizedFileURL
        }

        guard let animationProvider = NSItemProvider(contentsOf: animation) else {
            throw TestError("The animated icon file URL provider could not be created.")
        }
        guard model.useDroppedIcon([animationProvider]) else {
            throw TestError("The animated icon drop was not accepted.")
        }
        try await waitUntil {
            model.iconURL?.standardizedFileURL == animation.standardizedFileURL
                && model.iconAnimationData == animationData
        }
        model.selectIcon(nil)
        guard model.iconURL == nil, model.iconAnimationData == nil else {
            throw TestError("Removing the animated icon did not clear its preview data.")
        }

        guard let archiveProvider = NSItemProvider(contentsOf: archive) else {
            throw TestError("The archive file URL provider could not be created.")
        }
        guard model.openDroppedArchive([archiveProvider]) else {
            throw TestError("The Open drop was not accepted.")
        }
        try await waitUntil {
            model.openedArchive != nil || model.errorMessage != nil
        }
        if let errorMessage = model.errorMessage {
            throw TestError(errorMessage)
        }
        guard model.openedArchive?.manifest.title == "BundlePack Demo" else {
            throw TestError("The dropped package was not opened correctly.")
        }

        print("PASS: Finder icon metadata preserved package data; animated Create and Open drag-and-drop succeeded")
    }

    @MainActor
    private static func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw TestError("Timed out while waiting for the dropped item to load.")
    }

    private struct TestError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
