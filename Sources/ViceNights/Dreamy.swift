import AppKit

/// "Dreamy" night look: starburst flares on the wallpaper's real lights, light spilling onto
/// the ground, and a soft lavender haze with a big glare over everything.
enum Flare {
    nonisolated(unsafe) private static var cache: [String: CGImage] = [:]

    /// Soft radial light (colour at the centre fading to clear). Cached per colour/falloff.
    static func radial(_ color: UInt32, core: CGFloat = 0.75, mid: CGFloat = 0.22) -> CGImage? {
        let key = "\(color)-\(core)-\(mid)"
        if let c = cache[key] { return c }
        let size = 128
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let g = CGGradient(colorsSpace: space,
                           colors: [Palette.c(color, core), Palette.c(color, mid), Palette.c(color, 0)] as CFArray,
                           locations: [0, 0.3, 1])!
        let c = CGPoint(x: 64, y: 64)
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: 64, options: [])
        let image = ctx.makeImage()
        cache[key] = image
        return image
    }

    /// A camera-style starburst: glow, hot core and thin rays (long and short alternating).
    /// `radius` is the length of the long rays. The rays shimmer slowly.
    static func starburst(radius R: CGFloat, color: UInt32, spokes: Int = 4, thickness: CGFloat = 1.4,
                          animate: Bool = true) -> CALayer {
        let c = CALayer()
        c.bounds = CGRect(x: 0, y: 0, width: R * 2, height: R * 2)
        let center = CGPoint(x: R, y: R)

        let glow = CALayer()
        // A small, faint halo only: the look comes from the rays, not a disc of light.
        glow.bounds = CGRect(x: 0, y: 0, width: R * 0.55, height: R * 0.55)
        glow.position = center
        glow.contents = radial(color, core: 0.5, mid: 0.08)
        c.addSublayer(glow)

        let rays = CALayer()
        rays.frame = c.bounds
        let tilt = CGFloat.random(in: 0...(.pi / 4))
        for i in 0..<(spokes * 2) {
            let long = i % 2 == 0
            let length = R * 2 * (long ? 1 : 0.55)
            let ray = CAGradientLayer()
            ray.bounds = CGRect(x: 0, y: 0, width: length, height: thickness * (long ? 1 : 0.8))
            ray.position = center
            ray.colors = [Palette.c(color, 0), Palette.c(color, long ? 0.85 : 0.6), Palette.c(0xffffff, 0.95),
                          Palette.c(color, long ? 0.85 : 0.6), Palette.c(color, 0)]
            ray.locations = [0, 0.4, 0.5, 0.6, 1]
            ray.startPoint = CGPoint(x: 0, y: 0.5)
            ray.endPoint = CGPoint(x: 1, y: 0.5)
            ray.setAffineTransform(CGAffineTransform(rotationAngle: tilt + .pi * CGFloat(i) / CGFloat(spokes * 2)))
            rays.addSublayer(ray)
        }
        c.addSublayer(rays)

        let core = CALayer()
        core.bounds = CGRect(x: 0, y: 0, width: R * 0.28, height: R * 0.28)
        core.position = center
        core.contents = radial(0xffffff, core: 1, mid: 0.6)
        c.addSublayer(core)

        if animate && !Anim.reduceMotion {
            let shimmer = CABasicAnimation(keyPath: "transform.scale")
            shimmer.fromValue = 0.88
            shimmer.toValue = 1.08
            shimmer.duration = .random(in: 2.2...4)
            shimmer.autoreverses = true
            shimmer.repeatCount = .infinity
            shimmer.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            rays.add(Anim.throttle(Anim.randomPhase(shimmer), fps: 15), forKey: "shimmer")
            let turn = CABasicAnimation(keyPath: "transform.rotation.z")
            turn.fromValue = -0.06
            turn.toValue = 0.06
            turn.duration = .random(in: 9...14)
            turn.autoreverses = true
            turn.repeatCount = .infinity
            turn.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            c.add(Anim.throttle(Anim.randomPhase(turn), fps: 15), forKey: "turn")
        }
        return c
    }
}

/// Finds point lights (street lamps, signs, beacons) in a wallpaper so flares can sit on them.
enum LightFinder {
    /// Returns up to `maxCount` light positions, normalised 0…1 with a bottom-left origin,
    /// each with a strength 0…1.
    nonisolated static func find(in image: CGImage, maxCount: Int) -> [(CGPoint, CGFloat)] {
        let w = 192, h = max(1, Int(192 * CGFloat(image.height) / CGFloat(image.width)))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let data = ctx.data else { return [] }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = data.bindMemory(to: UInt8.self, capacity: w * h)
        func v(_ x: Int, _ y: Int) -> Int { Int(px[y * w + x]) }

        var candidates: [(x: Int, y: Int, score: Int)] = []
        let r = 4
        for y in r..<(h - r) {
            for x in r..<(w - r) {
                let c = v(x, y)
                guard c >= 215 else { continue }
                var isMax = true, sum = 0
                for dy in -r...r {
                    for dx in -r...r where dx != 0 || dy != 0 {
                        let n = v(x + dx, y + dy)
                        if n > c { isMax = false }
                        sum += n
                    }
                }
                guard isMax else { continue }
                let mean = sum / ((2 * r + 1) * (2 * r + 1) - 1)
                let contrast = c - mean
                if contrast >= 45 { candidates.append((x, y, contrast + c / 4)) }
            }
        }
        candidates.sort { $0.score > $1.score }
        var picked: [(CGPoint, CGFloat)] = []
        for cand in candidates {
            // Memory row 0 is the top of the image; convert to a bottom-left origin.
            let p = CGPoint(x: (CGFloat(cand.x) + 0.5) / CGFloat(w), y: 1 - (CGFloat(cand.y) + 0.5) / CGFloat(h))
            if picked.contains(where: { hypot($0.0.x - p.x, ($0.0.y - p.y) * CGFloat(h) / CGFloat(w)) < 0.07 }) { continue }
            picked.append((p, min(1, CGFloat(cand.score) / 220)))
            if picked.count == maxCount { break }
        }
        return picked
    }
}

/// Behind apps: starbursts on the wallpaper's lights and coloured light pooling on the ground.
/// Only a few lamps flare at once; every few seconds one fades out and another lamp lights up.
final class DreamyLightsLayer: CALayer {
    private var candidates: [(CGPoint, CGFloat)] = []
    private var active: [Int: CALayer] = [:]
    private var timer: Timer?
    private let maxActive = 4

    func setup(size: CGSize) {
        frame = CGRect(origin: .zero, size: size)
        compositingFilter = CIFilter(name: "CIScreenBlendMode")
        // Light spilling onto the street along the bottom of the screen.
        let pools: [(x: CGFloat, w: CGFloat, color: UInt32)] = [
            (0.18, 0.55, Palette.neonViolet), (0.55, 0.6, Palette.artPink), (0.88, 0.5, Palette.lavender),
        ]
        for p in pools {
            let l = CALayer()
            l.bounds = CGRect(x: 0, y: 0, width: size.width * p.w, height: size.height * 0.32)
            l.position = CGPoint(x: size.width * p.x, y: size.height * 0.02)
            l.contents = Flare.radial(p.color, core: 0.55, mid: 0.25)
            l.opacity = 0.55
            if !Anim.reduceMotion {
                let breathe = CABasicAnimation(keyPath: "opacity")
                breathe.fromValue = 0.35
                breathe.toValue = 0.65
                breathe.duration = .random(in: 5...8)
                breathe.autoreverses = true
                breathe.repeatCount = .infinity
                l.add(Anim.throttle(Anim.randomPhase(breathe), fps: 10), forKey: "breathe")
            }
            addSublayer(l)
        }
    }

    deinit { timer?.invalidate() }

    /// New set of lamp positions (view coordinates) for the current wallpaper.
    func showFlares(at points: [(CGPoint, CGFloat)]) {
        candidates = points
        for (_, layer) in active { fadeOut(layer) }
        active = [:]
        let first = Array(points.indices.shuffled().prefix(maxActive))
        for (n, i) in first.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(n) * 0.8) { [weak self] in self?.light(i) }
        }
        timer?.invalidate()
        guard !Anim.reduceMotion, points.count > 1 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: .random(in: 3.5...6), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.swapOne() }
        }
    }

    private func swapOne() {
        if let victim = active.keys.randomElement(), let layer = active.removeValue(forKey: victim) {
            fadeOut(layer)
        }
        let free = candidates.indices.filter { active[$0] == nil }
        if let next = free.randomElement() {
            DispatchQueue.main.asyncAfter(deadline: .now() + .random(in: 0.6...1.8)) { [weak self] in self?.light(next) }
        }
    }

    private func light(_ i: Int) {
        guard i < candidates.count, active[i] == nil, active.count < maxActive else { return }
        let (p, strength) = candidates[i]
        let colors: [UInt32] = [0xf1e8ff, 0xffd9f1, 0xdcd0ff, 0xfff1dd]
        let burst = Flare.starburst(radius: 40 + 70 * strength, color: colors[i % colors.count],
                                    spokes: i % 3 == 0 ? 4 : 3, thickness: 1.2 + strength)
        burst.position = p
        burst.opacity = 0
        addSublayer(burst)
        active[i] = burst
        Anim.fade(burst, to: Float(0.55 + 0.45 * strength), duration: 1.8)
    }

    private func fadeOut(_ layer: CALayer) {
        Anim.fade(layer, to: 0, duration: 1.6) { layer.removeFromSuperlayer() }
    }
}

/// Over (or behind) apps: lavender haze, a big glare at the top of the screen and a soft
/// violet vignette, all breathing slowly, the light-headed late-night feeling.
final class DreamyHazeView: LayerHostView {
    private var glare: CALayer?
    private var glareOpacity: Float = 0.3
    private var glareTimer: Timer?

    deinit { glareTimer?.invalidate() }

    /// A random screen corner, with the glare centred right on the edge so roughly half of it
    /// sits off-screen: it frames the display and never lands on your windows' content.
    private func edgeSpot() -> CGPoint {
        let W = bounds.width, H = bounds.height
        let jx = CGFloat.random(in: 0...(W * 0.03)), jy = CGFloat.random(in: 0...(H * 0.06))
        switch Int.random(in: 0..<4) {
        case 0: return CGPoint(x: jx, y: H - jy)          // top left
        case 1: return CGPoint(x: W - jx, y: H - jy)      // top right
        case 2: return CGPoint(x: jx, y: jy)              // bottom left
        default: return CGPoint(x: W - jx, y: jy)         // bottom right
        }
    }

    private func moveGlare(fadeIn: Bool) {
        guard let glare else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glare.position = edgeSpot()
        CATransaction.commit()
        Anim.fade(glare, to: glareOpacity, duration: 2.2)
        guard !Anim.reduceMotion else { return }
        glareTimer = Timer.scheduledTimer(withTimeInterval: .random(in: 12...25), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let glare = self.glare else { return }
                Anim.fade(glare, to: 0, duration: 1.8) { [weak self] in self?.moveGlare(fadeIn: true) }
            }
        }
    }

    init(size: CGSize, overApps: Bool) {
        super.init(size: size)
        let W = size.width, H = size.height
        let strength: Float = overApps ? 1 : 1.4

        let wash = CAGradientLayer()
        wash.frame = bounds
        wash.colors = [Palette.c(Palette.artPink, 0.09), Palette.c(Palette.lavender, 0.035), Palette.c(Palette.skyViolet, 0.11)]
        wash.locations = [0, 0.5, 1]
        wash.startPoint = CGPoint(x: 0.5, y: 0)
        wash.endPoint = CGPoint(x: 0.5, y: 1)
        root.addSublayer(wash)

        let vignette = CAGradientLayer()
        vignette.frame = bounds
        vignette.type = .radial
        vignette.colors = [Palette.c(Palette.skyViolet, 0), Palette.c(Palette.skyViolet, 0.22)]
        vignette.locations = [0.55, 1]
        vignette.startPoint = CGPoint(x: 0.5, y: 0.5)
        vignette.endPoint = CGPoint(x: 1.05, y: 1.1)
        root.addSublayer(vignette)

        // A soft glare that only ever sits near the screen's edges, never over the middle of
        // your work. Every so often it dims away and reappears somewhere else along the edge.
        let glare = Flare.starburst(radius: H * 0.11, color: 0xeadcff, spokes: 4, thickness: 1.5)
        glare.opacity = 0
        root.addSublayer(glare)
        self.glare = glare
        self.glareOpacity = 0.32 * strength
        moveGlare(fadeIn: true)

        let sideGlow = CALayer()
        sideGlow.bounds = CGRect(x: 0, y: 0, width: W * 0.7, height: H * 0.9)
        sideGlow.position = CGPoint(x: 0, y: H * 0.75)
        sideGlow.contents = Flare.radial(Palette.artPink, core: 0.5, mid: 0.18)
        sideGlow.opacity = 0.22 * strength
        root.addSublayer(sideGlow)

        root.opacity = strength > 1 ? 1 : 0.9
        if !Anim.reduceMotion {
            let breathe = CABasicAnimation(keyPath: "opacity")
            breathe.fromValue = 0.7
            breathe.toValue = 1
            breathe.duration = 7
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            wash.add(Anim.throttle(breathe, fps: 10), forKey: "breathe")
            let pulse = breathe.copy() as! CABasicAnimation
            pulse.duration = 9
            sideGlow.add(Anim.throttle(Anim.randomPhase(pulse), fps: 10), forKey: "breathe")
        }
    }
}
