import AppKit
import Foundation
import UniformTypeIdentifiers

extension AppModel {
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
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .svg, .gif]
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
                    self.errorMessage = "Drop a PNG, JPEG, TIFF, HEIC, SVG, or GIF image."
                    return
                }
                self.iconURL = url
                self.errorMessage = nil
            }
        }
        return true
    }

    func removeInput(_ url: URL) {
        inputURLs.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
    }

    @discardableResult
    func applyFinderIcon(_ iconData: Data, to url: URL) -> Bool {
        guard let image = NSImage(data: iconData) else { return false }
        return NSWorkspace.shared.setIcon(image, forFile: url.path, options: [])
    }

    func safeSuggestedName(_ value: String) -> String {
        value.components(separatedBy: CharacterSet(charactersIn: "/:\\"))
            .filter { !$0.isEmpty }
            .joined(separator: "-")
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
