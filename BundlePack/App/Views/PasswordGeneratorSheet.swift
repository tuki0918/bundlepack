import AppKit
import SwiftUI

struct PasswordGeneratorSheet: View {
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
