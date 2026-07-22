import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CreatePackageView: View {
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
                                        TextField(
                                            "At least \(BundlePackEncryptedContainer.minimumPasswordCharacters) characters",
                                            text: $model.encryptionPassword
                                        )
                                    } else {
                                        SecureField(
                                            "At least \(BundlePackEncryptedContainer.minimumPasswordCharacters) characters",
                                            text: $model.encryptionPassword
                                        )
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
        !model.encryptionEnabled || (model.encryptionPassword.count >= BundlePackEncryptedContainer.minimumPasswordCharacters
            && model.encryptionPassword == model.encryptionPasswordConfirmation
        )
    }

    private var passwordStatus: String {
        if model.encryptionPassword.count < BundlePackEncryptedContainer.minimumPasswordCharacters {
            return "At least \(BundlePackEncryptedContainer.minimumPasswordCharacters) characters required"
        }
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
