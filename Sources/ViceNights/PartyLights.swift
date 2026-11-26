import AppKit

/// Party lights: searchlight beams and lasers sweeping up from the bottom of the screen.
/// Drawn either inside the wallpaper (behind apps) or in their own
/// click-through window over everything, depending on the menu setting.
enum PartyLights {
    /// Builds the beams and lasers into `container`. Frame-rate capped; additive when behind apps.
    static func build(in container: CALayer, size: CGSize, additive: Bool) {
        let W = size.width, H = size.height
        // Screen blending only works within one window; over other apps we use plain alpha.
        let screenBlend: CIFilter? = additive ? CIFilter(name: "CIScreenBlendMode") : nil

        // Wide searchlight beams.
        let beamColors = [Palette.neonPink, Palette.neonCyan, Palette.neonViolet, Palette.artPink, Palette.neonCyan, Palette.neonPink]
        for (i, color) in beamColors.enumerated() {
            let length = H * 1.3
            let width = length * 0.13
            let beam = CAGradientLayer()
            beam.bounds = CGRect(x: 0, y: 0, width: width, height: length)
            beam.anchorPoint = CGPoint(x: 0.5, y: 0)
            beam.position = CGPoint(x: W * (0.08 + 0.168 * CGFloat(i)), y: -H * 0.03)
            beam.colors = [Palette.c(color, 0.38), Palette.c(color, 0.14), Palette.c(color, 0)]
            beam.locations = [0, 0.5, 1]
            beam.startPoint = CGPoint(x: 0.5, y: 0)
            beam.endPoint = CGPoint(x: 0.5, y: 1)
            beam.compositingFilter = screenBlend
            beam.mask = wedge(width: width, length: length, base: 8)
            let swing = CGFloat.random(in: 0.25...0.4)
            let start: CGFloat = (i % 2 == 0 ? -1 : 1) * swing
            beam.transform = CATransform3DMakeRotation(start, 0, 0, 1)
            let sweep = CABasicAnimation(keyPath: "transform.rotation.z")
            sweep.fromValue = start
            sweep.toValue = -start
            sweep.duration = .random(in: 7...13)
            sweep.autoreverses = true
            sweep.repeatCount = .infinity
            sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            beam.add(Anim.throttle(Anim.randomPhase(sweep), fps: 24), forKey: "sweep")
            container.addSublayer(beam)
        }

        // Thin lasers fanning out of the two bottom corners.
        for corner in 0..<2 {
            for j in 0..<3 {
                let color = [Palette.neonCyan, Palette.neonPink, Palette.neonViolet][(j + corner) % 3]
                let length = hypot(W, H)
                let laser = CALayer()
                laser.bounds = CGRect(x: 0, y: 0, width: 14, height: length)
                laser.anchorPoint = CGPoint(x: 0.5, y: 0)
                laser.position = CGPoint(x: corner == 0 ? W * 0.02 : W * 0.98, y: 0)
                laser.compositingFilter = screenBlend
                let glow = CAGradientLayer()
                glow.frame = laser.bounds
                glow.colors = [Palette.c(color, 0), Palette.c(color, 0.22), Palette.c(color, 0)]
                glow.startPoint = CGPoint(x: 0, y: 0.5)
                glow.endPoint = CGPoint(x: 1, y: 0.5)
                let core = CAGradientLayer()
                core.frame = CGRect(x: 6.25, y: 0, width: 1.5, height: length)
                core.colors = [Palette.c(color, 0.95), Palette.c(color, 0.5), Palette.c(color, 0)]
                core.locations = [0, 0.55, 1]
                core.startPoint = CGPoint(x: 0.5, y: 0)
                core.endPoint = CGPoint(x: 0.5, y: 1)
                laser.addSublayer(glow)
                laser.addSublayer(core)
                // Left corner aims up-right (negative rotation), right corner up-left.
                let dir: CGFloat = corner == 0 ? -1 : 1
                let from = dir * (0.15 + 0.12 * CGFloat(j))
                let to = dir * (0.75 + 0.1 * CGFloat(j))
                laser.transform = CATransform3DMakeRotation(from, 0, 0, 1)
                let sweep = CABasicAnimation(keyPath: "transform.rotation.z")
                sweep.fromValue = from
                sweep.toValue = to
                sweep.duration = .random(in: 2.8...4.5)
                sweep.autoreverses = true
                sweep.repeatCount = .infinity
                sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                laser.add(Anim.throttle(Anim.randomPhase(sweep), fps: 30), forKey: "sweep")
                // Lasers cut in and out like a light show.
                let blink = CAKeyframeAnimation(keyPath: "opacity")
                blink.values = [1, 1, 0, 0, 1]
                blink.keyTimes = [0, 0.55, 0.57, 0.85, 0.87]
                blink.duration = .random(in: 5...9)
                blink.repeatCount = .infinity
                laser.add(Anim.throttle(Anim.randomPhase(blink), fps: 30), forKey: "blink")
                container.addSublayer(laser)
            }
        }

    }

    private static func wedge(width: CGFloat, length: CGFloat, base: CGFloat) -> CALayer {
        let mask = CAShapeLayer()
        mask.frame = CGRect(x: 0, y: 0, width: width, height: length)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: width / 2 - base / 2, y: 0))
        p.addLine(to: CGPoint(x: width / 2 + base / 2, y: 0))
        p.addLine(to: CGPoint(x: width, y: length))
        p.addLine(to: CGPoint(x: 0, y: length))
        p.closeSubpath()
        mask.path = p
        return mask
    }
}

final class PartyLightsView: LayerHostView {
    override init(size: CGSize) {
        super.init(size: size)
        root.opacity = 0.8   // a touch softer when washing over app windows
        PartyLights.build(in: root, size: size, additive: false)
    }
}
