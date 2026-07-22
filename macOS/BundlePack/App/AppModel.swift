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
    @Published var isCancelling = false
    @Published var progressFraction: Double?
    @Published var operationWasCancelled = false
    @Published var statusMessage = ""
    @Published var errorMessage: String?

    private var decryptedTemporaryURL: URL?
    private var cancelActiveWork: (() -> Void)?

    private init() {}

    deinit {
        cancelActiveWork?()
        if let decryptedTemporaryURL {
            try? FileManager.default.removeItem(at: decryptedTemporaryURL)
        }
    }

    func createPackage() {
        guard !isWorking else { return }
        guard !inputURLs.isEmpty else {
            errorMessage = PackageBuilderError.noInputFiles.localizedDescription
            return
        }
        if encryptionEnabled {
            guard encryptionPassword.count >= BundlePackEncryptedContainer.minimumPasswordCharacters else {
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

        beginOperation(message: "Preparing files…")
        let progress = makeProgressHandler()
        let worker = Task.detached { try PackageBuilder.create(request, progress: progress) }
        cancelActiveWork = { worker.cancel() }
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await worker.value
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
            } catch is CancellationError {
                markCancelled("Package creation cancelled")
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = ""
            }
            finishOperation()
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
        beginOperation(message: "Reading package…")
        let progress = makeProgressHandler()
        let worker = Task.detached { () -> OpenResult in
            progress(BundlePackOperationProgress(fractionCompleted: 0.05, message: "Reading package…"))
            try Task.checkCancellation()
            let result: OpenResult
            if BundlePackEncryptedContainer.isEncrypted(url) {
                result = .encrypted(try BundlePackEncryptedContainer.readPublicInfo(from: url))
            } else {
                result = .unencrypted(try ZipArchiveInspector.inspect(url, progress: progress))
            }
            progress(BundlePackOperationProgress(fractionCompleted: 1, message: "Package validated"))
            return result
        }
        cancelActiveWork = { worker.cancel() }
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await worker.value
                clearDecryptedArchive()
                switch result {
                case .encrypted(let archive):
                    applyFinderIcon(archive.iconData, to: url)
                    lockedArchive = archive
                    openedArchive = nil
                    unlockPassword = ""
                    statusMessage = "Encrypted — enter the password to unlock"
                case .unencrypted(let archive):
                    applyFinderIcon(archive.iconData, to: url)
                    lockedArchive = nil
                    openedArchive = archive
                    statusMessage = "Warning: this package is not encrypted"
                }
                section = .open
            } catch is CancellationError {
                markCancelled("Opening cancelled")
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = ""
            }
            finishOperation()
        }
    }

    func unlockArchive() {
        guard !isWorking, let lockedArchive else { return }
        guard unlockPassword.count >= BundlePackEncryptedContainer.minimumPasswordCharacters else {
            errorMessage = BundlePackEncryptionError.passwordTooShort.localizedDescription
            return
        }

        clearDecryptedArchive()
        let decryptedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BundlePack-Decrypted-\(UUID().uuidString).zip")
        let password = unlockPassword
        beginOperation(message: "Decrypting package…")
        let progress = makeProgressHandler()
        let worker = Task.detached {
            try BundlePackEncryptedContainer.open(
                lockedArchive.url,
                password: password,
                to: decryptedURL,
                progress: { value in
                    progress(BundlePackOperationProgress(
                        fractionCompleted: value.fractionCompleted * 0.8,
                        message: value.message
                    ))
                }
            )
            let archive = try ZipArchiveInspector.inspect(
                decryptedURL,
                progress: { value in
                    progress(BundlePackOperationProgress(
                        fractionCompleted: 0.8 + value.fractionCompleted * 0.2,
                        message: "Validating decrypted contents…"
                    ))
                }
            )
            guard archive.iconData == lockedArchive.iconData else {
                throw BundlePackEncryptionError.invalidIcon
            }
            return archive
        }
        cancelActiveWork = { worker.cancel() }
        Task { [weak self] in
            guard let self else { return }
            do {
                let archive = try await worker.value
                decryptedTemporaryURL = decryptedURL
                openedArchive = archive
                unlockPassword = ""
                statusMessage = "Decrypted and validated"
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: decryptedURL)
                markCancelled("Unlock cancelled — package remains locked")
            } catch {
                try? FileManager.default.removeItem(at: decryptedURL)
                errorMessage = error.localizedDescription
                statusMessage = "Encrypted — package remains locked"
            }
            finishOperation()
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

        beginOperation(message: "Preparing extraction…")
        let progress = makeProgressHandler()
        let worker = Task.detached {
            try PackageBuilder.extract(archive, to: parent, progress: progress)
        }
        cancelActiveWork = { worker.cancel() }
        Task { [weak self] in
            guard let self else { return }
            do {
                let destination = try await worker.value
                statusMessage = "Extracted: \(destination.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch is CancellationError {
                markCancelled("Extraction cancelled")
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = ""
            }
            finishOperation()
        }
    }

    func cancelOperation() {
        guard isWorking, !isCancelling else { return }
        isCancelling = true
        statusMessage = "Cancelling…"
        cancelActiveWork?()
    }

    func clearDecryptedArchive() {
        if let decryptedTemporaryURL {
            try? FileManager.default.removeItem(at: decryptedTemporaryURL)
        }
        decryptedTemporaryURL = nil
        openedArchive = nil
    }

    private func beginOperation(message: String) {
        isWorking = true
        isCancelling = false
        operationWasCancelled = false
        progressFraction = 0
        statusMessage = message
    }

    private func finishOperation() {
        isWorking = false
        isCancelling = false
        progressFraction = nil
        cancelActiveWork = nil
    }

    private func markCancelled(_ message: String) {
        operationWasCancelled = true
        statusMessage = message
    }

    private func makeProgressHandler() -> BundlePackProgressHandler {
        { [weak self] value in
            Task { @MainActor [weak self] in
                guard let self, self.isWorking, !self.isCancelling else { return }
                self.progressFraction = value.fractionCompleted
                self.statusMessage = value.message
            }
        }
    }

    private enum OpenResult: Sendable {
        case encrypted(EncryptedBundlePackInfo)
        case unencrypted(BundlePackArchiveInfo)
    }
}
