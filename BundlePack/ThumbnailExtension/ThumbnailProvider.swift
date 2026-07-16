import AppKit
import QuickLookThumbnailing

final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        do {
            let iconData: Data
            if BundlePackEncryptedContainer.isEncrypted(request.fileURL) {
                iconData = try BundlePackEncryptedContainer.readPublicInfo(from: request.fileURL).iconData
            } else {
                iconData = try ZipArchiveInspector.embeddedIcon(in: request.fileURL)
            }
            guard let image = NSImage(data: iconData) else {
                throw BundlePackArchiveError.invalidEntry("icon.png")
            }

            let maximum = request.maximumSize
            let contextSize = CGSize(width: max(1, maximum.width), height: max(1, maximum.height))
            let reply = QLThumbnailReply(contextSize: contextSize, currentContextDrawing: {
                let target = aspectFit(image.size, in: NSRect(origin: .zero, size: contextSize))
                image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
                return true
            })
            handler(reply, nil)
        } catch {
            handler(nil, error)
        }
    }
}

private func aspectFit(_ source: NSSize, in target: NSRect) -> NSRect {
    guard source.width > 0, source.height > 0 else { return target }
    let scale = min(target.width / source.width, target.height / source.height)
    let size = NSSize(width: source.width * scale, height: source.height * scale)
    return NSRect(
        x: target.midX - size.width / 2,
        y: target.midY - size.height / 2,
        width: size.width,
        height: size.height
    )
}
