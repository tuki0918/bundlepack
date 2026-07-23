import AppKit
import SwiftUI

private enum PackageIconMetrics {
    static let size: CGFloat = 116
    static let cornerRadius: CGFloat = 24
    static let fallbackMarkSize: CGFloat = 100
}

struct PackageIconView: View {
    let image: NSImage?
    let animationData: Data?

    init(image: NSImage?, animationData: Data? = nil) {
        self.image = image
        self.animationData = animationData
    }

    var body: some View {
        Group {
            if let animationData {
                AnimatedPackageIconView(data: animationData)
            } else if let image {
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

private struct AnimatedPackageIconView: NSViewRepresentable {
    let data: Data

    final class Coordinator {
        var displayedData: Data?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageAlignment = .alignCenter
        view.imageScaling = .scaleProportionallyUpOrDown
        view.image = NSImage(data: data)
        view.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        context.coordinator.displayedData = data
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        if context.coordinator.displayedData != data {
            nsView.image = NSImage(data: data)
            context.coordinator.displayedData = data
        }
        nsView.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

struct IconDropTargetOverlay: View {
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

struct DropTargetOverlay: View {
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

struct BundlePackMark: View {
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
