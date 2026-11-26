import CoreGraphics
import Foundation

/// Renders a palm tree once into a bitmap: a gradient silhouette with a ringed trunk,
/// a two-colour neon rim light and a soft backlit glow, like the palms in the official key art.
/// Swaying a finished bitmap is just moving a texture, so it costs next to nothing to animate.
enum PalmArt {
    struct Style {
        var bottom: UInt32          // trunk-base colour
        var top: UInt32             // crown colour
        var rimLeft: UInt32         // rim light from the left…
        var rimRight: UInt32        // …and from the right
        var rimAlpha: CGFloat
        var rimWidth: CGFloat       // in points
        var glow: UInt32
        var glowAlpha: CGFloat
        var glowBlur: CGFloat       // in points

        /// Close to the viewer: nearly black, with a crisp neon edge.
        static let front = Style(bottom: 0x07070f, top: 0x161a30, rimLeft: Palette.neonPink, rimRight: Palette.neonCyan,
                                 rimAlpha: 0.85, rimWidth: 1.0, glow: Palette.neonViolet, glowAlpha: 0.55, glowBlur: 22)
        /// Further back: lighter and hazier, softer rim.
        static let back = Style(bottom: 0x141428, top: 0x2f3760, rimLeft: Palette.artPink, rimRight: Palette.neonViolet,
                                rimAlpha: 0.55, rimWidth: 1.2, glow: Palette.neonPink, glowAlpha: 0.35, glowBlur: 16)
    }

    struct Rendered {
        let image: CGImage
        /// Size in points.
        let size: CGSize
        /// Where the base of the trunk sits inside the image, in unit coordinates (use as anchorPoint).
        let anchor: CGPoint
    }

    static func render(height h: CGFloat, lean: CGFloat, fronds: Int, seed: UInt64,
                       style: Style, scale: CGFloat) -> Rendered? {
        let path = Shapes.palm(height: h, lean: lean, fronds: fronds, seed: seed, airy: true)
        let pad = style.glowBlur * 1.5
        let box = path.boundingBoxOfPath.insetBy(dx: -pad, dy: -pad).integral
        let pw = Int(ceil(box.width * scale)), ph = Int(ceil(box.height * scale))
        guard pw > 0, ph > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high

        // 1. Backlit glow (shadow blur ignores the CTM, so scale it by hand).
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: style.glowBlur * scale, color: Palette.c(style.glow, style.glowAlpha))
        ctx.addPath(path)
        ctx.setFillColor(Palette.c(style.bottom))
        ctx.fillPath()
        ctx.restoreGState()

        // 2. Body: dark at the roots, a little lighter up in the crown.
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        if let g = CGGradient(colorsSpace: space,
                              colors: [Palette.c(style.bottom), Palette.c(style.bottom), Palette.c(style.top)] as CFArray,
                              locations: [0, 0.35, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: h * 1.05),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }

        // 3. Trunk rings: faint bands across the trunk, closer together near the top.
        let crown = CGPoint(x: lean * h * 0.3, y: h)
        let bend = CGPoint(x: lean * h * 0.03, y: h * 0.55)
        let bw = h * 0.042, tw = h * 0.02
        ctx.setStrokeColor(Palette.c(style.top, 0.55))
        ctx.setLineWidth(max(0.6, h * 0.0035))
        var t: CGFloat = 0.04
        while t < 0.97 {
            let u = 1 - t
            let p = CGPoint(x: 2 * u * t * bend.x + t * t * crown.x, y: 2 * u * t * bend.y + t * t * crown.y)
            var tg = CGPoint(x: 2 * u * bend.x + 2 * t * (crown.x - bend.x), y: 2 * u * bend.y + 2 * t * (crown.y - bend.y))
            let m = max(0.0001, hypot(tg.x, tg.y))
            tg = CGPoint(x: tg.x / m, y: tg.y / m)
            let half = (bw + (tw - bw) * t) * 0.6
            ctx.move(to: CGPoint(x: p.x + tg.y * half, y: p.y - tg.x * half))
            ctx.addQuadCurve(to: CGPoint(x: p.x - tg.y * half, y: p.y + tg.x * half),
                             control: CGPoint(x: p.x - tg.x * half * 0.5, y: p.y - tg.y * half * 0.5))
            t += 0.028 + 0.018 * (1 - t)
        }
        ctx.strokePath()
        ctx.restoreGState()

        // 4. Rim light: an inner edge band, pink from one side fading to cyan from the other.
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.addPath(path)
        ctx.setLineWidth(style.rimWidth * 2)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        if let g = CGGradient(colorsSpace: space,
                              colors: [Palette.c(style.rimLeft, style.rimAlpha), Palette.c(style.rimLeft, style.rimAlpha * 0.15),
                                       Palette.c(style.rimRight, style.rimAlpha * 0.15), Palette.c(style.rimRight, style.rimAlpha)] as CFArray,
                              locations: [0, 0.42, 0.58, 1]) {
            let bb = path.boundingBoxOfPath
            ctx.drawLinearGradient(g, start: CGPoint(x: bb.minX, y: 0), end: CGPoint(x: bb.maxX, y: 0), options: [])
        }
        // Lights fade into the dark toward the roots.
        ctx.setBlendMode(.destinationOut)
        if let fade = CGGradient(colorsSpace: space, colors: [CGColor(gray: 0, alpha: 1), CGColor(gray: 0, alpha: 0)] as CFArray,
                                 locations: [0, 1]) {
            ctx.drawLinearGradient(fade, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: h * 0.6), options: [])
        }
        ctx.restoreGState()

        guard let image = ctx.makeImage() else { return nil }
        return Rendered(image: image, size: box.size,
                        anchor: CGPoint(x: -box.minX / box.width, y: -box.minY / box.height))
    }
}

/// Where the corner palms stand, in screen-local points (origin bottom-left).
enum CornerLayout {
    struct Palm {
        var base: CGPoint
        var height: CGFloat
        var lean: CGFloat
        var fronds: Int
        var seed: UInt64
        var front: Bool
    }

    /// A pair of hazy palms behind windows in each bottom corner, plus one dark foreground palm
    /// whose crown leans in from just off the edge and overlaps window corners a little.
    static func palms(screen: CGSize) -> [Palm] {
        let W = screen.width, H = screen.height
        let left: [Palm] = [
            Palm(base: CGPoint(x: W * 0.02, y: 0), height: H * 0.5, lean: 0.4, fronds: 10, seed: 41, front: false),
            Palm(base: CGPoint(x: W * 0.09, y: 0), height: H * 0.34, lean: -0.2, fronds: 9, seed: 43, front: false),
            Palm(base: CGPoint(x: -W * 0.05, y: -H * 0.02), height: H * 0.3, lean: 0.6, fronds: 11, seed: 47, front: true),
        ]
        let right = left.map { p -> Palm in
            var q = p
            q.base.x = W - p.base.x
            q.lean = -p.lean
            q.seed = p.seed + 100
            return q
        }
        return left + right
    }
}
