import AppKit
import SwiftUI

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
                if let progress = model.progressFraction {
                    ProgressView(value: progress)
                        .frame(width: 120)
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
            } else if model.operationWasCancelled {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Text(model.statusMessage)
                .font(.callout)
                .lineLimit(1)
            Spacer()
            if model.isWorking {
                Button(model.isCancelling ? "Cancelling…" : "Cancel") {
                    model.cancelOperation()
                }
                .disabled(model.isCancelling)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}
