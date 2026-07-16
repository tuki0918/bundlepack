import AppKit
import CoreGraphics
import Foundation

enum AppIconRenderError: LocalizedError {
    case invalidArguments
    case invalidSize
    case cannotCreateContext
    case cannotCreateGradient
    case symbolUnavailable
    case cannotEncodePNG

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "Usage: render-app-icon.swift OUTPUT.png SIZE"
        case .invalidSize:
            return "SIZE must be a positive integer."
        case .cannotCreateContext:
            return "The transparent bitmap context could not be created."
        case .cannotCreateGradient:
            return "The app icon gradient could not be created."
        case .symbolUnavailable:
            return "The shippingbox SF Symbol is unavailable."
        case .cannotEncodePNG:
            return "The rendered app icon could not be encoded as PNG."
        }
    }
}

func renderAppIcon(arguments: [String]) throws {
    guard arguments.count == 3 else { throw AppIconRenderError.invalidArguments }
    guard let pixelSize = Int(arguments[2]), pixelSize > 0 else {
        throw AppIconRenderError.invalidSize
    }

    let outputURL = URL(fileURLWithPath: arguments[1])
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: pixelSize * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw AppIconRenderError.cannotCreateContext
    }

    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    let scale = CGFloat(pixelSize) / 1024
    let iconRect = CGRect(x: 72 * scale, y: 72 * scale, width: 880 * scale, height: 880 * scale)
    let iconPath = CGPath(
        roundedRect: iconRect,
        cornerWidth: 220 * scale,
        cornerHeight: 220 * scale,
        transform: nil
    )

    // Keep these colors in sync with BundlePackMark in ContentView.swift.
    let startColor = NSColor(srgbRed: 0.12, green: 0.25, blue: 0.58, alpha: 1)
    let endColor = NSColor(srgbRed: 0.22, green: 0.62, blue: 0.86, alpha: 1)
    guard let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [startColor.cgColor, endColor.cgColor] as CFArray,
        locations: [0, 1]
    ) else {
        throw AppIconRenderError.cannotCreateGradient
    }

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -24 * scale),
        blur: 70 * scale,
        color: NSColor(srgbRed: 0.04, green: 0.18, blue: 0.48, alpha: 0.22).cgColor
    )
    context.addPath(iconPath)
    context.setFillColor(startColor.cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(iconPath)
    context.clip()
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: iconRect.minX, y: iconRect.maxY),
        end: CGPoint(x: iconRect.maxX, y: iconRect.minY),
        options: []
    )
    context.restoreGState()

    guard let baseSymbol = NSImage(systemSymbolName: "shippingbox", accessibilityDescription: nil) else {
        throw AppIconRenderError.symbolUnavailable
    }
    let pointConfiguration = NSImage.SymbolConfiguration(
        pointSize: iconRect.width * 0.46,
        weight: .semibold
    )
    let colorConfiguration = NSImage.SymbolConfiguration(paletteColors: [.white])
    guard let symbol = baseSymbol.withSymbolConfiguration(
        pointConfiguration.applying(colorConfiguration)
    ) else {
        throw AppIconRenderError.symbolUnavailable
    }

    let symbolRect = CGRect(
        x: iconRect.midX - symbol.size.width / 2,
        y: iconRect.midY - symbol.size.height / 2 - 8 * scale,
        width: symbol.size.width,
        height: symbol.size.height
    )

    NSGraphicsContext.saveGraphicsState()
    let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.current = graphicsContext
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -18 * scale),
        blur: 32 * scale,
        color: NSColor.black.withAlphaComponent(0.18).cgColor
    )
    symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)
    context.restoreGState()
    NSGraphicsContext.restoreGraphicsState()

    guard let renderedImage = context.makeImage(),
          let data = NSBitmapImageRep(cgImage: renderedImage)
            .representation(using: .png, properties: [:]) else {
        throw AppIconRenderError.cannotEncodePNG
    }

    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: outputURL, options: .atomic)
}

do {
    try renderAppIcon(arguments: CommandLine.arguments)
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
