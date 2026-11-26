import AppKit
import CoreImage
import ImageIO

/// Downloads official images from rockstargames.com on demand and keeps them in
/// ~/Library/Application Support/ViceNights/official. Nothing is bundled with the app.
@MainActor
final class ImageStore {
    static let shared = ImageStore()

    let directory: URL
    private var inFlight: [String: Task<URL?, Never>] = [:]

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("ViceNights/official", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func localURL(_ shot: Shot) -> URL { directory.appendingPathComponent(shot.cacheFileName) }

    func isCached(_ shot: Shot) -> Bool { FileManager.default.fileExists(atPath: localURL(shot).path) }

    func ensure(_ shot: Shot) async -> URL? {
        let dest = localURL(shot)
        if FileManager.default.fileExists(atPath: dest.path) { return dest }
        if let task = inFlight[shot.name] { return await task.value }
        let task = Task<URL?, Never> {
            var request = URLRequest(url: shot.remoteURL)
            request.timeoutInterval = 90
            do {
                let (tmp, response) = try await URLSession.shared.download(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tmp, to: dest)
                return dest
            } catch {
                NSLog("ViceNights: download failed for \(shot.name): \(error.localizedDescription)")
                return nil
            }
        }
        inFlight[shot.name] = task
        let result = await task.value
        inFlight[shot.name] = nil
        return result
    }

    private nonisolated static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// Lens colour fringing, baked in once per wallpaper: red is scaled very slightly outward from
    /// the centre and blue inward, so there's no split in the middle and a few pixels of red/blue
    /// fringe on bright edges toward the sides, like footage shot through a real lens.
    nonisolated static func lensFringe(_ image: CGImage, strength: CGFloat = 0.0024) -> CGImage? {
        let ci = CIImage(cgImage: image)
        let ext = ci.extent
        let c = CGPoint(x: ext.midX, y: ext.midY)
        func channel(_ v: (CGFloat, CGFloat, CGFloat), scale k: CGFloat) -> CIImage {
            let only = ci.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: v.0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: v.1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: v.2, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
            let t = CGAffineTransform(translationX: c.x, y: c.y).scaledBy(x: k, y: k).translatedBy(x: -c.x, y: -c.y)
            return only.clampedToExtent().transformed(by: t).cropped(to: ext)
        }
        let red = channel((1, 0, 0), scale: 1 + strength)
        let green = channel((0, 1, 0), scale: 1)
        let blue = channel((0, 0, 1), scale: 1 - strength)
        let rg = red.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: green])
        let rgb = blue.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: rg])
        return ciContext.createCGImage(rgb, from: ext)
    }

    /// Decode an image for a display of `pixelSize` (physical pixels), already cropped to the
    /// display's aspect ratio and `overscan` larger than it, so the drift can end at exactly one
    /// image pixel per screen pixel. Never upscales beyond the source, and never decodes more pixels
    /// than the display needs, which keeps memory to roughly one screen's worth per image.
    nonisolated static func decodeForDisplay(_ url: URL, pixelSize: CGSize, overscan: CGFloat, viceTint: Bool, fringe: Bool = false) -> CGImage? {
        autoreleasepool {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                  let iw = props[kCGImagePropertyPixelWidth] as? CGFloat,
                  let ih = props[kCGImagePropertyPixelHeight] as? CGFloat else { return nil }
            let target = CGSize(width: pixelSize.width * overscan, height: pixelSize.height * overscan)
            let fill = min(1, max(target.width / iw, target.height / ih))
            let maxPixel = Int((max(iw, ih) * fill).rounded(.up))
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard let scaled = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
            // Centre-crop to the display's aspect ratio.
            let sw = CGFloat(scaled.width), sh = CGFloat(scaled.height)
            let aspect = pixelSize.width / pixelSize.height
            var crop = CGRect(x: 0, y: 0, width: sw, height: sh)
            if sw / sh > aspect {
                crop.size.width = (sh * aspect).rounded()
                crop.origin.x = ((sw - crop.width) / 2).rounded()
            } else {
                crop.size.height = (sw / aspect).rounded()
                crop.origin.y = ((sh - crop.height) / 2).rounded()
            }
            var cropped = scaled.cropping(to: crop) ?? scaled
            if fringe, let f = lensFringe(cropped) { cropped = f }
            guard viceTint else { return cropped }
            // Bake the violet grade in once (soft light), rather than running a full-screen
            // blend filter on the GPU every frame.
            guard let ctx = CGContext(data: nil, width: cropped.width, height: cropped.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return cropped }
            let rect = CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height)
            ctx.draw(cropped, in: rect)
            ctx.setBlendMode(.softLight)
            ctx.setFillColor(Palette.c(Palette.skyViolet, 0.45))
            ctx.fill(rect)
            return ctx.makeImage() ?? cropped
        }
    }
}
