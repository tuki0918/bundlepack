import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Group {
                switch model.section {
                case .create:
                    CreatePackageView()
                case .open:
                    OpenPackageView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            if !model.statusMessage.isEmpty {
                statusBar
            }
        }
        .alert(
            "Unable to Complete",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "An unknown error occurred.")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            BundlePackMark(size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text("BundlePack")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text("Bundle files into one shareable package")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("View", selection: $model.section) {
                ForEach(AppModel.Section.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 210)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
    }

    private var statusBar: some View {
        HStack(spacing: 9) {
            if model.isWorking {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Text(model.statusMessage)
                .font(.callout)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct CreatePackageView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isPasswordGeneratorPresented = false
    @State private var isPasswordVisible = false
    @State private var isConfirmationVisible = false
    @State private var isInputDropTargeted = false
    @State private var isIconDropTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                sectionTitle("Package Information", detail: "Basic information shown after the package is unlocked.")

                HStack(alignment: .top, spacing: 20) {
                    iconPicker

                    VStack(spacing: 14) {
                        alignedFormRow("Name") {
                            TextField("Example: Project Assets", text: $model.title)
                                .textFieldStyle(.roundedBorder)
                        }
                        alignedFormRow("Version") {
                            TextField("1.0.0", text: $model.packageVersion)
                                .textFieldStyle(.roundedBorder)
                        }
                        alignedFormRow("Author") {
                            TextField("Optional", text: $model.author)
                                .textFieldStyle(.roundedBorder)
                        }
                        alignedFormRow("Description") {
                            TextField("Briefly describe the package", text: $model.summary, axis: .vertical)
                                .lineLimit(2...4)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                Divider()

                HStack(alignment: .firstTextBaseline) {
                    sectionTitle(
                        "Included Files",
                        detail: "Add files and folders to the same package."
                    )
                    Spacer()
                    Button {
                        model.chooseInputFiles()
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }

                inputList
                    .overlay {
                        if isInputDropTargeted {
                            DropTargetOverlay(
                                title: "Drop to Add Items",
                                systemImage: "plus.circle.fill"
                            )
                        }
                    }
                    .onDrop(
                        of: [UTType.fileURL.identifier],
                        isTargeted: $isInputDropTargeted,
                        perform: model.addDroppedInputItems
                    )

                Divider()

                sectionTitle(
                    "Protection Mode",
                    detail: "Choose encrypted protection or ZIP compatibility."
                )

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 4) {
                        protectionModeButton(
                            "Encrypted",
                            value: true
                        )
                        protectionModeButton(
                            "Unencrypted (ZIP Compatible)",
                            value: false
                        )
                    }
                    .padding(3)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.quaternary, lineWidth: 1)
                    )

                    if model.encryptionEnabled {
                        alignedFormRow("Password") {
                            HStack(spacing: 8) {
                                Group {
                                    if isPasswordVisible {
                                        TextField("At least 12 characters", text: $model.encryptionPassword)
                                    } else {
                                        SecureField("At least 12 characters", text: $model.encryptionPassword)
                                    }
                                }
                                .textFieldStyle(.roundedBorder)
                                Button {
                                    isPasswordVisible.toggle()
                                } label: {
                                    Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                                        .frame(width: 20)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .help(isPasswordVisible ? "Hide password" : "Show password")
                            }
                        }
                        alignedFormRow("Confirm") {
                            HStack(spacing: 8) {
                                Group {
                                    if isConfirmationVisible {
                                        TextField("Enter the same password again", text: $model.encryptionPasswordConfirmation)
                                    } else {
                                        SecureField("Enter the same password again", text: $model.encryptionPasswordConfirmation)
                                    }
                                }
                                .textFieldStyle(.roundedBorder)
                                Button {
                                    isConfirmationVisible.toggle()
                                } label: {
                                    Image(systemName: isConfirmationVisible ? "eye.slash.fill" : "eye.fill")
                                        .frame(width: 20)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .help(isConfirmationVisible ? "Hide password confirmation" : "Show password confirmation")
                            }
                        }
                        HStack {
                            Label(
                                passwordStatus,
                                systemImage: passwordIsValid ? "checkmark.shield.fill" : "lock.trianglebadge.exclamationmark"
                            )
                            .font(.caption)
                            .foregroundStyle(passwordIsValid ? .green : .secondary)
                            Spacer()
                            Button("Generate Password…") {
                                isPasswordGeneratorPresented = true
                            }
                        }
                    } else {
                        Label(
                            "This package will be a standard ZIP. File names, metadata, and contents will remain visible to scanners.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.callout)
                        .foregroundStyle(.orange)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.quaternary, lineWidth: 1)
                )

                HStack {
                    Text(model.encryptionEnabled
                         ? "Share the password separately from the package. BundlePack does not save it."
                         : "Rename the extension to .zip to open it with a standard archive utility.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        model.createPackage()
                    } label: {
                        Label("Create BundlePack…", systemImage: "shippingbox.fill")
                            .frame(minWidth: 160)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.inputURLs.isEmpty || !passwordIsValid || model.isWorking)
                }
            }
            .padding(28)
            .padding(.bottom, model.statusMessage.isEmpty ? 0 : 40)
        }
        .sheet(isPresented: $isPasswordGeneratorPresented) {
            PasswordGeneratorSheet { password in
                model.encryptionPassword = password
                model.encryptionPasswordConfirmation = password
            }
        }
    }

    private var passwordIsValid: Bool {
        !model.encryptionEnabled || (model.encryptionPassword.count >= 12
            && model.encryptionPassword == model.encryptionPasswordConfirmation
        )
    }

    private var passwordStatus: String {
        if model.encryptionPassword.count < 12 { return "At least 12 characters required" }
        if model.encryptionPassword != model.encryptionPasswordConfirmation { return "Password confirmation does not match" }
        return "Ready to encrypt"
    }

    private func protectionModeButton(
        _ title: String,
        value: Bool
    ) -> some View {
        let isSelected = model.encryptionEnabled == value
        return Button {
            withAnimation(.easeInOut(duration: 0.12)) {
                model.encryptionEnabled = value
            }
        } label: {
            HStack(spacing: 6) {
                if value {
                    Image(systemName: "lock.fill")
                } else {
                    Image(systemName: "shippingbox")
                }
                Text(title)
            }
            .font(.callout.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func alignedFormRow<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .frame(width: 88, alignment: .trailing)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var iconPicker: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                PackageIconView(image: selectedIconImage)
                    .overlay {
                        if isIconDropTargeted {
                            IconDropTargetOverlay()
                        }
                    }
                    .onDrop(
                        of: [UTType.fileURL.identifier],
                        isTargeted: $isIconDropTargeted,
                        perform: model.useDroppedIcon
                    )

                if model.iconURL != nil {
                    Button {
                        model.iconURL = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(.black.opacity(0.72), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Use Default Icon")
                    .accessibilityLabel("Use Default Icon")
                    .offset(x: 5, y: -5)
                }
            }

            Button("Choose Icon…") { model.chooseIcon() }
                .buttonStyle(.link)
            Text("or drop an image")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(width: 136)
    }

    private var selectedIconImage: NSImage? {
        if let iconURL = model.iconURL, let image = NSImage(contentsOf: iconURL) {
            return image
        }
        guard let defaultIconURL = Bundle.main.url(
            forResource: "DefaultPackageIcon",
            withExtension: "png"
        ) else {
            return nil
        }
        return NSImage(contentsOf: defaultIconURL)
    }

    @ViewBuilder
    private var inputList: some View {
        if model.inputURLs.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.secondary)
                Text("No files added yet")
                    .font(.headline)
                Text("Drag files or folders here")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Choose Files or Folders…") { model.chooseInputFiles() }
            }
            .frame(maxWidth: .infinity, minHeight: 146)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            )
        } else {
            VStack(spacing: 0) {
                ForEach(model.inputURLs, id: \.standardizedFileURL) { url in
                    HStack(spacing: 12) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                            Text(url.deletingLastPathComponent().path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button {
                            model.removeInput(url)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove from the package")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    if url != model.inputURLs.last { Divider().padding(.leading, 58) }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            )
        }
    }

    private func sectionTitle(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title3.weight(.semibold))
            Text(detail).font(.callout).foregroundStyle(.secondary)
        }
    }
}

private struct PasswordGeneratorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onUse: (String) -> Void

    @State private var totalLength = 16
    @State private var digitCount = 4
    @State private var symbolCount = 4
    @State private var generatedPassword = ""
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(systemName: "key.horizontal.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 46, height: 46)
                    .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Password Generator")
                        .font(.title2.weight(.semibold))
                    Text("Choose the exact length and character counts.")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Generated Password")
                        .font(.headline)
                    Spacer()
                    Text("\(generatedPassword.count) characters")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                TextField("Select Generate to create a password", text: $generatedPassword)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .privacySensitive()
                Label(
                    "The password is shown in plain text for review. A copied password is cleared after 60 seconds if the clipboard is unchanged.",
                    systemImage: "eye.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                settingRow("Total Length", value: totalLength) {
                    Stepper("", value: $totalLength, in: 12...128)
                        .labelsHidden()
                }
                Divider()
                settingRow("Digits", value: digitCount) {
                    Stepper("", value: $digitCount, in: 0...maximumDigitCount)
                        .labelsHidden()
                }
                Divider()
                settingRow("Symbols", value: symbolCount) {
                    Stepper("", value: $symbolCount, in: 0...maximumSymbolCount)
                        .labelsHidden()
                }
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Letters")
                        Text("Includes at least one uppercase and one lowercase letter")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(letterCount)")
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 30, alignment: .trailing)
                }
                .padding(12)
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.quaternary, lineWidth: 1)
            )

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button {
                    copyToClipboard()
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .disabled(generatedPassword.isEmpty)

                Button("Generate") { generatePassword() }

                Button("Use Password") {
                    onUse(generatedPassword)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(generatedPassword.count < 12)
            }
        }
        .padding(26)
        .frame(width: 540)
        .onAppear { generatePassword() }
        .onChange(of: totalLength) { _, _ in normalizeCounts() }
        .onChange(of: digitCount) { _, _ in normalizeCounts() }
        .onChange(of: symbolCount) { _, _ in normalizeCounts() }
        .onChange(of: generatedPassword) { _, _ in copied = false }
        .onDisappear { generatedPassword = "" }
    }

    private var letterCount: Int {
        totalLength - digitCount - symbolCount
    }

    private var maximumDigitCount: Int {
        max(0, totalLength - symbolCount - 2)
    }

    private var maximumSymbolCount: Int {
        max(0, totalLength - digitCount - 2)
    }

    private func settingRow<Control: View>(
        _ label: String,
        value: Int,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value)")
                .font(.body.monospacedDigit())
                .frame(minWidth: 30, alignment: .trailing)
            control()
        }
        .padding(12)
    }

    private func normalizeCounts() {
        digitCount = min(digitCount, max(0, totalLength - symbolCount - 2))
        symbolCount = min(symbolCount, max(0, totalLength - digitCount - 2))
    }

    private func generatePassword() {
        normalizeCounts()
        generatedPassword = BundlePackPasswordGenerator.generate(
            totalLength: totalLength,
            digitCount: digitCount,
            symbolCount: symbolCount
        )
    }

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        copied = pasteboard.setString(generatedPassword, forType: .string)
        guard copied else { return }

        let copiedPassword = generatedPassword
        let copiedChangeCount = pasteboard.changeCount
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard !Task.isCancelled else { return }
            let currentPasteboard = NSPasteboard.general
            guard currentPasteboard.changeCount == copiedChangeCount,
                  currentPasteboard.string(forType: .string) == copiedPassword else {
                return
            }
            currentPasteboard.clearContents()
        }
    }
}

private struct OpenPackageView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isArchiveDropTargeted = false

    var body: some View {
        Group {
            if let archive = model.openedArchive {
                archiveDetail(archive)
            } else if let archive = model.lockedArchive {
                lockedArchiveView(archive)
            } else {
                emptyState
            }
        }
        .padding(.bottom, model.statusMessage.isEmpty ? 0 : 40)
        .overlay {
            if isArchiveDropTargeted {
                DropTargetOverlay(
                    title: "Drop BundlePack to Open",
                    systemImage: "doc.badge.arrow.up.fill"
                )
                .padding(20)
            }
        }
        .onDrop(
            of: [UTType.fileURL.identifier],
            isTargeted: $isArchiveDropTargeted,
            perform: model.openDroppedArchive
        )
    }

    private func lockedArchiveView(_ archive: EncryptedBundlePackInfo) -> some View {
        VStack(spacing: 24) {
            Spacer()
            PackageIconView(image: NSImage(data: archive.iconData))

            VStack(spacing: 8) {
                Label("Encrypted BundlePack", systemImage: "lock.fill")
                    .font(.title2.weight(.semibold))
                Text("File names and contents remain hidden until the package is unlocked.")
                    .foregroundStyle(.secondary)
                Text("Original size: \(ByteCountFormatter.string(fromByteCount: Int64(archive.originalArchiveSize), countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 10) {
                SecureField("Password", text: $model.unlockPassword)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                    .onSubmit { model.unlockArchive() }
                Button {
                    model.unlockArchive()
                } label: {
                    Label("Unlock", systemImage: "lock.open.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.unlockPassword.count < 12 || model.isWorking)
            }

            HStack(spacing: 14) {
                Label("AES-256-GCM", systemImage: "checkmark.shield.fill")
                Label("PBKDF2-SHA256", systemImage: "key.fill")
                Label("File List Hidden", systemImage: "eye.slash.fill")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button("Open Another Package…") { model.chooseArchive() }
            Spacer()
        }
        .padding(28)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            BundlePackMark(size: 88)
            VStack(spacing: 6) {
                Text("Open a BundlePack")
                    .font(.title2.weight(.semibold))
                Text("Validate a .bundlepack file, review its contents, and extract it safely.")
                    .foregroundStyle(.secondary)
                Text("You can also drag a .bundlepack file into this window.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            Button("Choose Package…") { model.chooseArchive() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func archiveDetail(_ archive: BundlePackArchiveInfo) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 22) {
                PackageIconView(image: NSImage(data: archive.iconData))

                VStack(alignment: .leading, spacing: 8) {
                    Text(archive.manifest.title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    HStack(spacing: 10) {
                        metadataPill("v\(archive.manifest.packageVersion.isEmpty ? "—" : archive.manifest.packageVersion)")
                        metadataPill("\(archive.payloadFiles.count) files")
                        metadataPill(ByteCountFormatter.string(fromByteCount: Int64(archive.expandedSize), countStyle: .file))
                    }
                    if !archive.manifest.author.isEmpty {
                        Label(archive.manifest.author, systemImage: "person.crop.circle")
                            .foregroundStyle(.secondary)
                    }
                    if !archive.manifest.summary.isEmpty {
                        Text(archive.manifest.summary)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                Spacer()
            }
            .padding(28)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Contents").font(.headline)
                    Spacer()
                    Text("Compressed: \(ByteCountFormatter.string(fromByteCount: Int64(archive.archiveSize), countStyle: .file))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                List(archive.payloadFiles) { file in
                    HStack(spacing: 10) {
                        Image(systemName: "doc")
                            .foregroundStyle(.secondary)
                        Text(file.path).lineLimit(1)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.inset)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )

                HStack {
                    Button("Open Another Package…") { model.chooseArchive() }
                    Spacer()
                    Label("Paths Validated", systemImage: "checkmark.shield.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        model.extractOpenedArchive()
                    } label: {
                        Label("Extract Safely…", systemImage: "archivebox.fill")
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.isWorking)
                }
            }
            .padding(24)
        }
    }

    private func metadataPill(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.quaternary, in: Capsule())
    }
}

private enum PackageIconMetrics {
    static let size: CGFloat = 116
    static let cornerRadius: CGFloat = 24
    static let fallbackMarkSize: CGFloat = 100
}

private struct PackageIconView: View {
    let image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                BundlePackMark(size: PackageIconMetrics.fallbackMarkSize)
            }
        }
        .frame(width: PackageIconMetrics.size, height: PackageIconMetrics.size)
        .background(
            RoundedRectangle(cornerRadius: PackageIconMetrics.cornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .clipShape(
            RoundedRectangle(cornerRadius: PackageIconMetrics.cornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PackageIconMetrics.cornerRadius, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
        .accessibilityLabel("Package icon")
    }
}

private struct IconDropTargetOverlay: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 24, weight: .semibold))
            Text("Drop Image")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(Color.accentColor)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: PackageIconMetrics.cornerRadius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: PackageIconMetrics.cornerRadius, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                }
        }
        .overlay(
            RoundedRectangle(cornerRadius: PackageIconMetrics.cornerRadius, style: .continuous)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
        )
        .clipShape(
            RoundedRectangle(cornerRadius: PackageIconMetrics.cornerRadius, style: .continuous)
        )
        .allowsHitTesting(false)
    }
}

private struct DropTargetOverlay: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .semibold))
            Text(title)
                .font(.headline)
        }
        .foregroundStyle(Color.accentColor)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.accentColor.opacity(0.10))
                }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7]))
        )
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .allowsHitTesting(false)
    }
}

private struct BundlePackMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.12, green: 0.25, blue: 0.58), Color(red: 0.22, green: 0.62, blue: 0.86)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "shippingbox")
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        }
        .frame(width: size, height: size)
        .shadow(color: .blue.opacity(0.2), radius: size * 0.12, y: size * 0.06)
    }
}
