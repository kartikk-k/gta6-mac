import AppKit

extension NSWindow.Level {
    /// Above the menu bar and the Dock so the neon frame runs unbroken around the display.
    /// Menus and pop-ups (popUpMenu level) still draw on top of it.
    static let edgeGlow = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
}

/// A thin neon tube hugging the display edge, pink → violet → cyan flowing slowly around it,
/// with a soft inward bloom.
///
/// Cost: the bloom is a static stack of strokes (no shadows, rasterised once); the only thing
/// that animates is the conic gradient's angle, capped at a low frame rate.
final class EdgeGlowView: LayerHostView {
    /// MacBook displays are rounded at the top only; a generous radius keeps the tube inside
    /// the visible panel instead of running off under the physical corner.
    static let cornerRadius: CGFloat = 18
    /// Bloom + core: (stroke width, alpha), widest first. Strokes are centred on a path at the
    /// screen edge, so only their inner half shows. Alphas are solved so the stacked strokes
    /// composite to a smooth exponential falloff (≈0.42·e^(−d/6.5)) out to ~24pt.
    static let strokes: [(width: CGFloat, alpha: CGFloat)] = {
        let distances: [CGFloat] = stride(from: 24, through: 1.5, by: -1.5).map { $0 }
        func target(_ d: CGFloat) -> CGFloat { 0.42 * exp(-d / 6.5) }
        var result: [(CGFloat, CGFloat)] = []
        var outer: CGFloat = 0   // composite alpha already provided by wider strokes
        for d in distances {
            let want = target(d)
            let a = max(0, 1 - (1 - want) / (1 - outer))
            result.append((d * 2, a))
            outer = want
        }
        result.append((3.0, 1.0))   // the bright neon tube itself (~1.5pt visible)
        return result
    }()
    /// Path inset from the physical edge.
    static let inset: CGFloat = 1.2

    private let frameLayer = CALayer()
    private let gradient = CAGradientLayer()
    private var flickerTimer: Timer?

    init(screen: NSScreen) {
        super.init(size: screen.frame.size)
        let scale = screen.backingScaleFactor

        frameLayer.frame = bounds
        root.addSublayer(frameLayer)

        gradient.frame = bounds
        gradient.type = .conic
        let pink = Palette.c(Palette.neonPink), violet = Palette.c(Palette.neonViolet), cyan = Palette.c(Palette.neonCyan)
        gradient.colors = [pink, violet, cyan, violet, pink]
        gradient.locations = [0, 0.25, 0.5, 0.75, 1]
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.mask = Self.makeMask(bounds: bounds, scale: scale)
        frameLayer.addSublayer(gradient)

        if !Anim.reduceMotion {
            // Flow the colours around the frame by turning the conic gradient's angle.
            let steps = 48
            var points: [NSValue] = []
            for i in 0...steps {
                let a = CGFloat(i) / CGFloat(steps) * 2 * .pi
                points.append(NSValue(point: CGPoint(x: 0.5 + cos(a) * 0.5, y: 0.5 + sin(a) * 0.5)))
            }
            let flow = CAKeyframeAnimation(keyPath: "endPoint")
            flow.values = points
            flow.duration = 40
            flow.repeatCount = .infinity
            flow.calculationMode = .linear
            gradient.add(Anim.throttle(flow, fps: 8), forKey: "flow")
            scheduleFlicker()
        }
    }

    deinit { flickerTimer?.invalidate() }

    /// Rounded top corners, square bottom corners (y-up coordinates), like the MacBook panel.
    static func topRounded(_ r: CGRect, radius: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX - radius, y: r.maxY), radius: radius)
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY - radius), radius: radius)
        p.closeSubpath()
        return p
    }

    /// Static mask: stacked rounded-rect strokes approximating a glow falloff, rasterised once.
    private static func makeMask(bounds: CGRect, scale: CGFloat) -> CALayer {
        let mask = CALayer()
        mask.frame = bounds
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let path = topRounded(rect, radius: cornerRadius)
        for s in strokes {
            let l = CAShapeLayer()
            l.frame = bounds
            l.path = path
            l.fillColor = nil
            l.strokeColor = CGColor(gray: 1, alpha: s.alpha)
            l.lineWidth = s.width
            l.contentsScale = scale
            mask.addSublayer(l)
        }
        // The mask never changes; cache it as a bitmap so only the gradient is redrawn.
        mask.shouldRasterize = true
        mask.rasterizationScale = scale
        return mask
    }

    /// Every 20–40s the tube stutters gently, like a real neon sign.
    private func scheduleFlicker() {
        flickerTimer = Timer.scheduledTimer(withTimeInterval: .random(in: 20...40), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let a = CAKeyframeAnimation(keyPath: "opacity")
                a.values = [1, 0.45, 1, 0.7, 1, 0.85, 1]
                a.keyTimes = [0, 0.1, 0.22, 0.36, 0.5, 0.72, 1]
                a.duration = 0.5
                self.frameLayer.add(a, forKey: "flicker")
                self.scheduleFlicker()
            }
        }
    }
}
