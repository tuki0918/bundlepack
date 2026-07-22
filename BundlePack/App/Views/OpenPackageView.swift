import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct OpenPackageView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isArchiveDropTargeted = false
    @State private var isUnlockPasswordVisible = false

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
                Group {
                    if isUnlockPasswordVisible {
                        TextField("Password", text: $model.unlockPassword)
                    } else {
                        SecureField("Password", text: $model.unlockPassword)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onSubmit { model.unlockArchive() }
                Button {
                    isUnlockPasswordVisible.toggle()
                } label: {
                    Image(systemName: isUnlockPasswordVisible ? "eye.slash.fill" : "eye.fill")
                        .frame(width: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(isUnlockPasswordVisible ? "Hide password" : "Show password")
                .accessibilityLabel(isUnlockPasswordVisible ? "Hide password" : "Show password")
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
