import AppKit
import CoreImage

/// "Neon Skyline": an original, generated Vice-City-inspired night scene in the site's palette.
/// Static parts are rendered once into an image; lights, the Ferris wheel and palms are live layers.
enum SkylineScene {
    private struct Building {
        var rect: CGRect
        var color: UInt32
        var lit: Double
        var neon: UInt32?
        var spire: CGFloat
        var stepped: Bool
    }

    private struct Light {
        var rect: CGRect
        var color: UInt32
    }

    static func build(size: CGSize, scale: CGFloat) -> CALayer {
        let W = size.width, H = size.height
        let horizon = (H * 0.30).rounded()
        var rng = RNG(0x5EED_71CE)

        // MARK: Generate the city

        var far: [Building] = [], low: [Building] = [], downtown: [Building] = []
        var x: CGFloat = -10
        while x < W {
            let w = rng.r(0.012, 0.032) * W, h = rng.r(0.035, 0.13) * H
            far.append(Building(rect: CGRect(x: x, y: horizon, width: w, height: h), color: 0x2a2352,
                                lit: 0.12, neon: nil, spire: 0, stepped: false))
            x += w * rng.r(0.7, 1.0)
        }
        x = -10
        while x < W {
            let w = rng.r(0.01, 0.03) * W, h = rng.r(0.008, 0.045) * H
            low.append(Building(rect: CGRect(x: x, y: horizon, width: w, height: h), color: 0x1a1733,
                                lit: 0.2, neon: nil, spire: 0, stepped: false))
            x += w * rng.r(0.85, 1.05)
        }
        let center = W * 0.5
        let neons = [Palette.neonPink, Palette.neonCyan, Palette.neonViolet, Palette.neonPink]
        for _ in 0..<46 {
            let cx = center + W * 0.19 * (rng.r(-1, 1) + rng.r(-1, 1))
            let w = rng.r(0.014, 0.038) * W
            let d = (cx - center) / (W * 0.2)
            let peak = exp(-d * d)
            let h = H * (0.045 + 0.36 * peak * rng.r(0.4, 1.0))
            downtown.append(Building(
                rect: CGRect(x: cx - w / 2, y: horizon, width: w, height: h),
                color: rng.pick([0x131129, 0x161430, 0x1b1838]),
                lit: rng.r(0.3, 0.55),
                neon: rng.chance(0.25) ? rng.pick(neons) : nil,
                spire: rng.chance(0.18) ? rng.r(0.02, 0.06) * H : 0,
                stepped: rng.chance(0.35)))
        }
        downtown.sort { $0.rect.height > $1.rect.height }   // tall ones behind

        let wheelR = H * 0.085
        let wheelCenter = CGPoint(x: W * 0.755, y: horizon + wheelR + H * 0.014)
        var twinkles: [Light] = []
        var beacons: [CGPoint] = []

        // MARK: City image (transparent background, so it can be mirrored into the water)

        let city = render(size: size, scale: scale) { ctx in
            for b in far {
                fill(ctx, b.rect, b.color)
                windows(ctx, b, cell: CGSize(width: 5, height: 7), win: CGSize(width: 1.2, height: 1.4), rng: &rng, twinkles: &twinkles)
            }
            for b in downtown {
                // Facade lit faintly from below by the city, rim-lit on top by the pink sky glow.
                fillGradient(ctx, b.rect, bottom: 0x241d4a, top: b.color)
                fill(ctx, CGRect(x: b.rect.minX, y: b.rect.minY, width: 1, height: b.rect.height), 0x3b3172, alpha: 0.7)
                fill(ctx, CGRect(x: b.rect.minX, y: b.rect.maxY - 1, width: b.rect.width, height: 1), Palette.artPink, alpha: 0.22)
                if b.stepped {
                    let s = CGRect(x: b.rect.midX - b.rect.width * 0.3, y: b.rect.maxY,
                                   width: b.rect.width * 0.6, height: b.rect.height * 0.05)
                    fill(ctx, s, b.color)
                }
                var top = CGPoint(x: b.rect.midX, y: b.rect.maxY + (b.stepped ? b.rect.height * 0.05 : 0))
                if b.spire > 0 {
                    ctx.setStrokeColor(Palette.c(b.color))
                    ctx.setLineWidth(1.6)
                    ctx.move(to: top)
                    ctx.addLine(to: CGPoint(x: top.x, y: top.y + b.spire))
                    ctx.strokePath()
                    top.y += b.spire
                }
                if b.rect.height > H * 0.2 || b.spire > 0 { beacons.append(top) }
                // Floodlit crowns on the tallest towers.
                if b.rect.height > H * 0.22 {
                    ctx.saveGState()
                    ctx.clip(to: b.rect)
                    let glowColor = b.neon ?? Palette.lavender
                    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                       colors: [Palette.c(glowColor, 0.35), Palette.c(glowColor, 0)] as CFArray,
                                       locations: [0, 1])!
                    let c = CGPoint(x: b.rect.midX, y: b.rect.maxY)
                    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: b.rect.width * 1.1, options: [])
                    ctx.restoreGState()
                }
                // A few LED facades: vertical light bars.
                if b.neon != nil && b.rect.height > H * 0.12 && rng.chance(0.4) {
                    let color = b.neon!
                    var lx = b.rect.minX + 3
                    while lx < b.rect.maxX - 3 {
                        fill(ctx, CGRect(x: lx, y: b.rect.minY + b.rect.height * 0.08, width: 1.1, height: b.rect.height * 0.84), color, alpha: 0.45)
                        lx += 6
                    }
                }
                windows(ctx, b, cell: CGSize(width: 4.5, height: 6), win: CGSize(width: 2.2, height: 3),
                        rng: &rng, twinkles: &twinkles, collect: true)
                if let neon = b.neon {
                    ctx.saveGState()
                    ctx.setShadow(offset: .zero, blur: 9, color: Palette.c(neon, 0.95))
                    ctx.setStrokeColor(Palette.c(neon, 0.95))
                    ctx.setLineWidth(1.4)
                    let r = b.rect
                    ctx.move(to: CGPoint(x: r.minX, y: r.maxY - r.height * 0.25))
                    ctx.addLine(to: CGPoint(x: r.minX, y: r.maxY))
                    ctx.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
                    ctx.addLine(to: CGPoint(x: r.maxX, y: r.maxY - r.height * 0.25))
                    ctx.strokePath()
                    if rng.chance(0.5) {
                        ctx.move(to: CGPoint(x: r.midX, y: r.maxY - 6))
                        ctx.addLine(to: CGPoint(x: r.midX, y: r.minY + r.height * 0.35))
                        ctx.strokePath()
                    }
                    ctx.restoreGState()
                }
            }
            for b in low {
                fill(ctx, b.rect, b.color)
                windows(ctx, b, cell: CGSize(width: 4, height: 4), win: CGSize(width: 1.6, height: 1.6), rng: &rng, twinkles: &twinkles)
            }
            // Street-light glitter along the waterfront.
            for _ in 0..<Int(W / 3) {
                let p = CGPoint(x: rng.r(0, W), y: horizon + rng.r(0, H * 0.008))
                fill(ctx, CGRect(x: p.x, y: p.y, width: 1.2, height: 1.2),
                     rng.pick([Palette.warmWindow, Palette.warmWindow, Palette.artPink]), alpha: rng.r(0.4, 0.95))
            }
            // Ferris wheel legs.
            ctx.setStrokeColor(Palette.c(0x1b1838))
            ctx.setLineWidth(3)
            ctx.move(to: CGPoint(x: wheelCenter.x - wheelR * 0.55, y: horizon))
            ctx.addLine(to: wheelCenter)
            ctx.addLine(to: CGPoint(x: wheelCenter.x + wheelR * 0.55, y: horizon))
            ctx.strokePath()
        }

        // MARK: Main image: sky, moon, city, water

        let image = render(size: size, scale: scale) { ctx in
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let skyColors = [0x0e0d22, 0x15142f, 0x1f1b42, 0x302862, 0x4f3c86, 0x8a5a9c, 0xd9839a]
                .map { Palette.c(UInt32($0)) } as CFArray
            let skyLocations: [CGFloat] = [0, 0.22, 0.45, 0.66, 0.82, 0.94, 1]
            let sky = CGGradient(colorsSpace: space, colors: skyColors, locations: skyLocations)!
            ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: horizon), options: [])

            for _ in 0..<170 {
                let r = rng.r(0.35, 1.1)
                let p = CGPoint(x: rng.r(0, W), y: rng.r(horizon + H * 0.3, H))
                ctx.setFillColor(Palette.c(rng.chance(0.7) ? 0xffffff : Palette.lavender, rng.r(0.25, 0.9)))
                ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            }

            let moon = CGPoint(x: W * 0.74, y: H * 0.8), mr = H * 0.021
            let glow = CGGradient(colorsSpace: space,
                                  colors: [Palette.c(0xe9c9ef, 0.22), Palette.c(0xb79be0, 0.06), Palette.c(0xb79be0, 0)] as CFArray,
                                  locations: [0, 0.4, 1])!
            ctx.drawRadialGradient(glow, startCenter: moon, startRadius: mr, endCenter: moon, endRadius: mr * 6, options: [])
            ctx.setFillColor(Palette.c(0xf7ecf4))
            ctx.fillEllipse(in: CGRect(x: moon.x - mr, y: moon.y - mr, width: mr * 2, height: mr * 2))

            // Long, low clouds lit pink from the city below.
            for i in 0..<9 {
                let cy = horizon + H * rng.r(0.08, 0.32)
                let cx = rng.r(0, W)
                let cw = W * rng.r(0.18, 0.4), chh = H * rng.r(0.008, 0.02)
                let lit = 1 - (cy - horizon) / (H * 0.34)
                let tone: UInt32 = i % 3 == 0 ? Palette.artPink : 0x6a4f9a
                ctx.saveGState()
                ctx.translateBy(x: cx, y: cy)
                ctx.scaleBy(x: cw / chh, y: 1)
                let cg = CGGradient(colorsSpace: space,
                                    colors: [Palette.c(tone, 0.38 * lit), Palette.c(tone, 0)] as CFArray,
                                    locations: [0, 1])!
                ctx.drawRadialGradient(cg, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: chh, options: [])
                ctx.restoreGState()
            }

            // Pink city haze rising off the horizon.
            ctx.saveGState()
            ctx.translateBy(x: W * 0.5, y: horizon)
            ctx.scaleBy(x: 1, y: 0.35)
            let haze = CGGradient(colorsSpace: space,
                                  colors: [Palette.c(Palette.neonPink, 0.34), Palette.c(Palette.artPink, 0.1), Palette.c(Palette.artPink, 0)] as CFArray,
                                  locations: [0, 0.5, 1])!
            ctx.drawRadialGradient(haze, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: W * 0.6, options: [])
            ctx.restoreGState()

            if let city { ctx.draw(city, in: CGRect(origin: .zero, size: size)) }

            // Water
            let water = CGRect(x: 0, y: 0, width: W, height: horizon)
            ctx.saveGState()
            ctx.clip(to: water)
            let waterGrad = CGGradient(colorsSpace: space,
                                       colors: [Palette.c(0x2a1f4d), Palette.c(0x0c0a1c), Palette.c(0x05040c)] as CFArray,
                                       locations: [0, 0.5, 1])!
            ctx.drawLinearGradient(waterGrad, start: CGPoint(x: 0, y: horizon), end: .zero, options: [])
            if let city, let soft = blurred(city, sigma: 4 * scale) {
                ctx.saveGState()
                ctx.setAlpha(0.55)
                ctx.translateBy(x: 0, y: horizon * 2)
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(soft, in: CGRect(origin: .zero, size: size))
                ctx.restoreGState()
            }
            var y: CGFloat = 0
            while y < horizon {
                ctx.setFillColor(Palette.c(0x05040c, rng.r(0.2, 0.6)))
                ctx.fill(CGRect(x: 0, y: y, width: W, height: rng.r(0.6, 1.8)))
                y += rng.r(1.8, 4.5)
            }
            // Neon towers smear long coloured streaks down the water.
            for b in downtown {
                guard let neon = b.neon else { continue }
                let streak = CGRect(x: b.rect.midX - b.rect.width * 0.18, y: horizon - b.rect.height * 0.9,
                                    width: b.rect.width * 0.36, height: b.rect.height * 0.9)
                let sg = CGGradient(colorsSpace: space,
                                    colors: [Palette.c(neon, 0), Palette.c(neon, 0.28)] as CFArray,
                                    locations: [0, 1])!
                ctx.saveGState()
                ctx.clip(to: streak)
                ctx.drawLinearGradient(sg, start: CGPoint(x: 0, y: streak.minY), end: CGPoint(x: 0, y: streak.maxY), options: [])
                ctx.restoreGState()
            }
            ctx.restoreGState()
            ctx.setFillColor(Palette.c(Palette.artPink, 0.25))
            ctx.fill(CGRect(x: 0, y: horizon - 0.5, width: W, height: 1))
        }

        let container = CALayer()
        container.frame = CGRect(origin: .zero, size: size)
        container.contents = image
        container.contentsGravity = .resize
        container.contentsScale = scale

        // MARK: Live layers

        // Windows switching on and off.
        for light in twinkles.prefix(80) {
            let l = CALayer()
            l.frame = light.rect
            l.backgroundColor = Palette.c(light.color, 0.9)
            let on = rng.chance(0.5)
            let a = CAKeyframeAnimation(keyPath: "opacity")
            let t1 = Double(rng.r(0.1, 0.45)), t2 = Double(rng.r(0.55, 0.9))
            let v0: Float = on ? 1 : 0, v1: Float = on ? 0 : 1
            a.values = [v0, v0, v1, v1, v0, v0]
            a.keyTimes = [0, t1, t1 + 0.002, t2, t2 + 0.002, 1].map { NSNumber(value: $0) }
            a.duration = Double(rng.r(14, 50))
            a.repeatCount = .infinity
            l.opacity = v0
            l.add(Anim.throttle(Anim.randomPhase(a), fps: 10), forKey: "twinkle")
            container.addSublayer(l)
        }

        // Red aircraft-warning beacons on the tallest towers.
        for p in beacons.prefix(8) {
            let l = CALayer()
            l.bounds = CGRect(x: 0, y: 0, width: 2.6, height: 2.6)
            l.cornerRadius = 1.3
            l.position = CGPoint(x: p.x, y: p.y + 1.5)
            l.backgroundColor = Palette.c(0xff3b3b)
            l.shadowColor = Palette.c(0xff3b3b)
            l.shadowRadius = 4
            l.shadowOpacity = 1
            l.shadowOffset = .zero
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 1
            a.toValue = 0.08
            a.duration = 1.3
            a.autoreverses = true
            a.repeatCount = .infinity
            l.add(Anim.throttle(Anim.randomPhase(a), fps: 15), forKey: "blink")
            container.addSublayer(l)
        }

        container.addSublayer(ferrisWheel(center: wheelCenter, radius: wheelR, scale: scale))

        // Light glinting on the water.
        for _ in 0..<60 {
            let l = CALayer()
            let w = rng.r(5, 26)
            let gx = W * 0.5 + W * 0.2 * (rng.r(-1, 1) + rng.r(-1, 1))
            l.frame = CGRect(x: gx, y: rng.r(horizon * 0.2, horizon * 0.97), width: w, height: 1.2)
            l.backgroundColor = Palette.c(rng.pick([Palette.warmWindow, Palette.artPink, Palette.neonCyan]), 0.8)
            l.cornerRadius = 0.6
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 0.05
            a.toValue = Float(rng.r(0.4, 0.9))
            a.duration = Double(rng.r(1.4, 3.8))
            a.autoreverses = true
            a.repeatCount = .infinity
            l.add(Anim.throttle(Anim.randomPhase(a), fps: 15), forKey: "glint")
            container.addSublayer(l)
        }

        // Foreground palms framing the view.
        let palms: [(x: CGFloat, h: CGFloat, lean: CGFloat, seed: UInt64)] = [
            (0.03, 0.5, 0.3, 3), (0.085, 0.36, 0.5, 5), (0.97, 0.47, -0.35, 9), (0.925, 0.33, -0.55, 13),
        ]
        for p in palms {
            let l = CAShapeLayer()
            l.path = Shapes.palm(height: H * p.h, lean: p.lean, fronds: 10, seed: p.seed)
            l.fillColor = Palette.c(0x07060f)
            l.contentsScale = scale
            l.bounds = .zero
            l.position = CGPoint(x: W * p.x, y: -H * 0.02)
            if !Anim.reduceMotion { sway(l, amount: 0.012) }
            container.addSublayer(l)
        }
        return container
    }

    // MARK: Helpers

    static func sway(_ l: CALayer, amount: CGFloat) {
        let a = CABasicAnimation(keyPath: "transform.rotation.z")
        a.fromValue = -amount
        a.toValue = amount
        a.duration = Double.random(in: 4.5...7)
        a.autoreverses = true
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        l.add(Anim.throttle(Anim.randomPhase(a), fps: 20), forKey: "sway")
    }

    private static func ferrisWheel(center: CGPoint, radius R: CGFloat, scale: CGFloat) -> CALayer {
        let holder = CALayer()
        holder.bounds = .zero
        holder.position = center
        let wheel = CALayer()
        wheel.bounds = .zero
        holder.addSublayer(wheel)

        let spokes = CAShapeLayer()
        let sp = CGMutablePath()
        for i in 0..<16 {
            let a = CGFloat(i) / 16 * 2 * .pi
            sp.move(to: .zero)
            sp.addLine(to: CGPoint(x: cos(a) * R, y: sin(a) * R))
        }
        sp.addEllipse(in: CGRect(x: -R * 0.93, y: -R * 0.93, width: R * 1.86, height: R * 1.86))
        spokes.path = sp
        spokes.strokeColor = Palette.c(Palette.lavender, 0.38)
        spokes.fillColor = nil
        spokes.lineWidth = 0.7
        spokes.contentsScale = scale
        wheel.addSublayer(spokes)

        let ring = CAShapeLayer()
        ring.path = CGPath(ellipseIn: CGRect(x: -R, y: -R, width: R * 2, height: R * 2), transform: nil)
        ring.strokeColor = Palette.c(Palette.neonPink)
        ring.fillColor = nil
        ring.lineWidth = 1.8
        ring.shadowColor = Palette.c(Palette.neonPink)
        ring.shadowRadius = 6
        ring.shadowOpacity = 1
        ring.shadowOffset = .zero
        ring.contentsScale = scale
        let cycle = CAKeyframeAnimation(keyPath: "strokeColor")
        let colors = [Palette.neonPink, Palette.neonViolet, Palette.neonCyan, Palette.neonPink].map { Palette.c($0) }
        cycle.values = colors
        cycle.duration = 9
        cycle.repeatCount = .infinity
        ring.add(Anim.throttle(cycle, fps: 10), forKey: "cycle")
        let shadowCycle = cycle.copy() as! CAKeyframeAnimation
        shadowCycle.keyPath = "shadowColor"
        ring.add(Anim.throttle(shadowCycle, fps: 10), forKey: "cycleShadow")
        wheel.addSublayer(ring)

        for i in 0..<16 {
            let a = CGFloat(i) / 16 * 2 * .pi
            let g = CALayer()
            g.bounds = CGRect(x: 0, y: 0, width: 3.4, height: 3.4)
            g.cornerRadius = 1.7
            g.position = CGPoint(x: cos(a) * R, y: sin(a) * R)
            g.backgroundColor = Palette.c(i % 2 == 0 ? Palette.neonCyan : Palette.warmWindow)
            wheel.addSublayer(g)
        }

        if !Anim.reduceMotion {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = 2 * CGFloat.pi
            spin.duration = 150
            spin.repeatCount = .infinity
            wheel.add(Anim.throttle(spin, fps: 15), forKey: "spin")
        }
        return holder
    }

    private static func fillGradient(_ ctx: CGContext, _ r: CGRect, bottom: UInt32, top: UInt32) {
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                           colors: [Palette.c(bottom), Palette.c(top)] as CFArray, locations: [0, 1])!
        ctx.saveGState()
        ctx.clip(to: r)
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: r.minY), end: CGPoint(x: 0, y: r.minY + min(r.height, 260)), options: [.drawsAfterEndLocation])
        ctx.restoreGState()
    }

    private static func fill(_ ctx: CGContext, _ r: CGRect, _ color: UInt32, alpha: CGFloat = 1) {
        ctx.setFillColor(Palette.c(color, alpha))
        ctx.fill(r)
    }

    private static func windows(_ ctx: CGContext, _ b: Building, cell: CGSize, win: CGSize,
                                rng: inout RNG, twinkles: inout [Light], collect: Bool = false) {
        let r = b.rect.insetBy(dx: 2.5, dy: 0)
        var y = r.minY + 3
        while y + win.height < r.maxY - 3 {
            let rowLit = rng.chance(0.75) ? b.lit : b.lit * 0.2
            var x = r.minX
            while x + win.width < r.maxX {
                let rect = CGRect(x: x, y: y, width: win.width, height: win.height)
                let roll = rng.next()
                let color: UInt32 = roll < 0.7 ? Palette.warmWindow : (roll < 0.9 ? Palette.coolWindow : Palette.artPink)
                if rng.chance(rowLit) {
                    fill(ctx, rect, color, alpha: rng.r(0.6, 1.0))
                }
                if collect, rng.chance(0.004) {
                    twinkles.append(Light(rect: rect, color: color))
                }
                x += cell.width
            }
            y += cell.height
        }
    }

    private static func render(size: CGSize, scale: CGFloat, _ draw: (CGContext) -> Void) -> CGImage? {
        let pw = Int(size.width * scale), ph = Int(size.height * scale)
        guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        draw(ctx)
        return ctx.makeImage()
    }

    private static func blurred(_ image: CGImage, sigma: CGFloat) -> CGImage? {
        let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let ci = CIImage(cgImage: image).clampedToExtent().applyingGaussianBlur(sigma: Double(sigma)).cropped(to: extent)
        return CIContext(options: nil).createCGImage(ci, from: extent)
    }
}
