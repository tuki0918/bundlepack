import AppKit
import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let bundlePack = UTType(exportedAs: "com.tuki0918.bundlepack", conformingTo: .data)
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    enum Section: String, CaseIterable, Identifiable {
        case create = "Create"
        case open = "Open"

        var id: String { rawValue }
    }

    @Published var section: Section = .create
    @Published var title = ""
    @Published var packageVersion = "1.0.0"
    @Published var author = ""
    @Published var summary = ""
    @Published var inputURLs: [URL] = []
    @Published var iconURL: URL?
    @Published var encryptionEnabled = true
    @Published var encryptionPassword = ""
    @Published var encryptionPasswordConfirmation = ""
    @Published var unlockPassword = ""
    @Published var lockedArchive: EncryptedBundlePackInfo?
    @Published var openedArchive: BundlePackArchiveInfo?
    @Published var isWorking = false
    @Published var statusMessage = ""
    @Published var errorMessage: String?

    private var decryptedTemporaryURL: URL?

    private init() {}

    deinit {
        if let decryptedTemporaryURL {
            try? FileManager.default.removeItem(at: decryptedTemporaryURL)
        }
    }

    func chooseInputFiles() {
        let panel = NSOpenPanel()
        panel.title = "Choose Files or Folders to Include"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK else { return }
        addInputURLs(panel.urls)
    }

    func addInputURLs(_ urls: [URL]) {
        let existing = Set(inputURLs.map(\.standardizedFileURL))
        inputURLs.append(contentsOf: urls.filter { !existing.contains($0.standardizedFileURL) })
        if title.isEmpty, let first = inputURLs.first {
            title = first.deletingPathExtension().lastPathComponent
        }
    }

    func addDroppedInputItems(_ providers: [NSItemProvider]) -> Bool {
        let compatibleProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        for provider in compatibleProviders {
            loadDroppedFileURL(from: provider) { [weak self] url in
                guard let url else { return }
                Task { @MainActor [weak self] in
                    self?.addInputURLs([url])
                }
            }
        }
        return !compatibleProviders.isEmpty
    }

    func openDroppedArchive(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else {
            return false
        }

        loadDroppedFileURL(from: provider) { [weak self] url in
            guard let url else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard url.pathExtension.lowercased() == "bundlepack" else {
                    self.errorMessage = "Drop a .bundlepack file to open it."
                    return
                }
                self.openArchive(url)
            }
        }
        return true
    }

    func chooseIcon() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Package Icon"
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .svg]
        guard panel.runModal() == .OK else { return }
        iconURL = panel.url
    }

    func useDroppedIcon(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else {
            return false
        }

        loadDroppedFileURL(from: provider) { [weak self] url in
            guard let url else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let image = NSImage(contentsOf: url),
                      image.size.width > 0,
                      image.size.height > 0 else {
                    self.errorMessage = "Drop a PNG, JPEG, TIFF, HEIC, or SVG image."
                    return
                }
                self.iconURL = url
                self.errorMessage = nil
            }
        }
        return true
    }

    func createPackage() {
        guard !isWorking else { return }
        guard !inputURLs.isEmpty else {
            errorMessage = PackageBuilderError.noInputFiles.localizedDescription
            return
        }
        if encryptionEnabled {
            guard encryptionPassword.count >= 12 else {
                errorMessage = BundlePackEncryptionError.passwordTooShort.localizedDescription
                return
            }
            guard encryptionPassword == encryptionPasswordConfirmation else {
                errorMessage = "The password confirmation does not match."
                return
            }
        }

        let savePanel = NSSavePanel()
        savePanel.title = "Save BundlePack"
        savePanel.allowedContentTypes = [.bundlePack]
        savePanel.canCreateDirectories = true
        let suggested = safeSuggestedName(title.isEmpty ? "Untitled" : title)
        savePanel.nameFieldStringValue = "\(suggested).bundlepack"
        guard savePanel.runModal() == .OK, let destination = savePanel.url else { return }
        guard let fallbackIconURL = Bundle.main.url(forResource: "DefaultPackageIcon", withExtension: "png") else {
            errorMessage = "The built-in package icon could not be loaded."
            return
        }

        let request = PackageCreationRequest(
            title: title,
            packageVersion: packageVersion,
            author: author,
            summary: summary,
            inputURLs: inputURLs,
            iconURL: iconURL,
            fallbackIconURL: fallbackIconURL,
            encryptionEnabled: encryptionEnabled,
            password: encryptionPassword,
            destinationURL: destination
        )

        isWorking = true
        statusMessage = "Packing files…"
        Task {
            do {
                let result = try await Task.detached { try PackageBuilder.create(request) }.value
                clearDecryptedArchive()
                switch result {
                case .encrypted(let archive):
                    applyFinderIcon(archive.iconData, to: destination)
                    lockedArchive = archive
                    openedArchive = nil
                    unlockPassword = ""
                    statusMessage = "Created encrypted package: \(destination.lastPathComponent)"
                case .unencrypted(let archive):
                    applyFinderIcon(archive.iconData, to: destination)
                    lockedArchive = nil
                    openedArchive = archive
                    statusMessage = "Created unencrypted ZIP-compatible package — names and contents are visible"
                }
                encryptionPassword = ""
                encryptionPasswordConfirmation = ""
                section = .open
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = ""
            }
            isWorking = false
        }
    }

    func chooseArchive() {
        let panel = NSOpenPanel()
        panel.title = "Open BundlePack"
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.bundlePack]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openArchive(url)
    }

    func openArchive(_ url: URL) {
        guard !isWorking else { return }
        isWorking = true
        statusMessage = "Validating…"
        Task {
            do {
                let result = try await Task.detached { () -> OpenResult in
                    if BundlePackEncryptedContainer.isEncrypted(url) {
                        return .encrypted(try BundlePackEncryptedContainer.readPublicInfo(from: url))
                    }
                    return .legacy(try ZipArchiveInspector.inspect(url))
                }.value
                clearDecryptedArchive()
                switch result {
                case .encrypted(let archive):
                    applyFinderIcon(archive.iconData, to: url)
                    lockedArchive = archive
                    openedArchive = nil
                    unlockPassword = ""
                    statusMessage = "Encrypted — enter the password to unlock"
                case .legacy(let archive):
                    applyFinderIcon(archive.iconData, to: url)
                    lockedArchive = nil
                    openedArchive = archive
                    statusMessage = "Warning: this package is not encrypted"
                }
                section = .open
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = ""
            }
            isWorking = false
        }
    }

    func unlockArchive() {
        guard !isWorking, let lockedArchive else { return }
        guard unlockPassword.count >= 12 else {
            errorMessage = BundlePackEncryptionError.passwordTooShort.localizedDescription
            return
        }

        clearDecryptedArchive()
        let decryptedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BundlePack-Decrypted-\(UUID().uuidString).zip")
        let password = unlockPassword
        isWorking = true
        statusMessage = "Decrypting and validating contents…"

        Task {
            do {
                let archive = try await Task.detached {
                    try BundlePackEncryptedContainer.open(lockedArchive.url, password: password, to: decryptedURL)
                    return try ZipArchiveInspector.inspect(decryptedURL)
                }.value
                decryptedTemporaryURL = decryptedURL
                openedArchive = archive
                unlockPassword = ""
                statusMessage = "Decrypted and validated"
            } catch {
                try? FileManager.default.removeItem(at: decryptedURL)
                errorMessage = error.localizedDescription
                statusMessage = "Encrypted — package remains locked"
            }
            isWorking = false
        }
    }

    func extractOpenedArchive() {
        guard !isWorking, let archive = openedArchive else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose an Extraction Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Extract Here"
        guard panel.runModal() == .OK, let parent = panel.url else { return }

        isWorking = true
        statusMessage = "Validating and extracting safely…"
        Task {
            do {
                let destination = try await Task.detached {
                    try PackageBuilder.extract(archive.url, to: parent)
                }.value
                statusMessage = "Extracted: \(destination.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = ""
            }
            isWorking = false
        }
    }

    func removeInput(_ url: URL) {
        inputURLs.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
    }

    @discardableResult
    func applyFinderIcon(_ iconData: Data, to url: URL) -> Bool {
        guard let image = NSImage(data: iconData) else { return false }
        return NSWorkspace.shared.setIcon(image, forFile: url.path, options: [])
    }

    private func safeSuggestedName(_ value: String) -> String {
        value.components(separatedBy: CharacterSet(charactersIn: "/:\\"))
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    private func clearDecryptedArchive() {
        if let decryptedTemporaryURL {
            try? FileManager.default.removeItem(at: decryptedTemporaryURL)
        }
        decryptedTemporaryURL = nil
        openedArchive = nil
    }

    private enum OpenResult: Sendable {
        case encrypted(EncryptedBundlePackInfo)
        case legacy(BundlePackArchiveInfo)
    }
}

private func loadDroppedFileURL(
    from provider: NSItemProvider,
    completion: @escaping (URL?) -> Void
) {
    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
        if let url = item as? URL {
            completion(url)
        } else if let url = item as? NSURL {
            completion(url as URL)
        } else if let data = item as? Data {
            completion(URL(dataRepresentation: data, relativeTo: nil))
        } else if let string = item as? String {
            completion(URL(string: string))
        } else {
            completion(nil)
        }
    }
}
