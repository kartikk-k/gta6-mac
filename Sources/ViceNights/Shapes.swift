import CoreGraphics
import Foundation

/// Vector silhouettes. All paths use a y-up coordinate space (like CALayer on macOS).
enum Shapes {
    // MARK: Palm tree (base of trunk at the origin)

    /// Slim curved trunk with a crown of long, arching fronds whose leaflets hang down like
    /// feathers (after the silhouettes in the official "Out Now" banner).
    static func palm(height h: CGFloat, lean: CGFloat, fronds n: Int = 9, seed: UInt64) -> CGPath {
        var rng = RNG(seed)
        let p = CGMutablePath()
        let crown = CGPoint(x: lean * h * 0.3, y: h)
        let bw = h * 0.042, tw = h * 0.02
        let bend = CGPoint(x: lean * h * 0.03, y: h * 0.55)
        // Trunk (clockwise, like the fronds, so the union fills cleanly).
        p.move(to: CGPoint(x: -bw / 2, y: 0))
        p.addQuadCurve(to: CGPoint(x: crown.x - tw / 2, y: crown.y),
                       control: CGPoint(x: bend.x - (bw + tw) / 4, y: bend.y))
        p.addLine(to: CGPoint(x: crown.x + tw / 2, y: crown.y))
        p.addQuadCurve(to: CGPoint(x: bw / 2, y: 0),
                       control: CGPoint(x: bend.x + (bw + tw) / 4, y: bend.y))
        p.closeSubpath()
        // Fronds fan out from just right of horizontal-down, over the top, to left-down.
        // The crown tilts a little with the lean.
        for i in 0..<n {
            let t = CGFloat(i) / CGFloat(max(1, n - 1))
            var angle = CGFloat.pi * (-0.24 + 1.48 * t) + rng.r(-0.08, 0.08) + lean * 0.25
            // Pull the near-vertical fronds sideways a touch so the top doesn't bristle.
            let up = sin(angle)
            if up > 0.75 { angle += (cos(angle) >= 0 ? -1 : 1) * 0.35 }
            let sideways = abs(cos(angle))
            let length = h * rng.r(0.58, 0.74) * (0.75 + 0.3 * sideways)
            addFrond(p, from: crown, angle: angle, length: length, rng: &rng)
        }
        return p
    }

    private static func addFrond(_ p: CGMutablePath, from c: CGPoint, angle: CGFloat, length L: CGFloat,
                                 rng: inout RNG) {
        let dx = cos(angle), dy = sin(angle)
        // The rib rises out of the crown, arches, then droops toward the tip.
        let ctrl = CGPoint(x: c.x + dx * L * 0.6, y: c.y + dy * L * 0.45 + L * 0.22)
        let tip = CGPoint(x: c.x + dx * L * 0.92, y: c.y + dy * L * 0.2 - L * 0.48)
        func point(_ t: CGFloat) -> CGPoint {
            let u = 1 - t
            return CGPoint(x: u * u * c.x + 2 * u * t * ctrl.x + t * t * tip.x,
                           y: u * u * c.y + 2 * u * t * ctrl.y + t * t * tip.y)
        }
        func tangent(_ t: CGFloat) -> CGPoint {
            let x = 2 * (1 - t) * (ctrl.x - c.x) + 2 * t * (tip.x - ctrl.x)
            let y = 2 * (1 - t) * (ctrl.y - c.y) + 2 * t * (tip.y - ctrl.y)
            let m = max(0.0001, hypot(x, y))
            return CGPoint(x: x / m, y: y / m)
        }
        func unit(_ v: CGPoint) -> CGPoint {
            let m = max(0.0001, hypot(v.x, v.y))
            return CGPoint(x: v.x / m, y: v.y / m)
        }
        // Leaflets: narrow blades spaced along both sides of a thin rib, with gaps between them.
        // The side facing the ground gets long hanging blades, the upper side short ones; all sweep
        // back toward the crown.
        let count = 17
        let rib = L * 0.011
        var plus: [CGPoint] = [], minus: [CGPoint] = []
        for side in [CGFloat(1), -1] {
            var pts: [CGPoint] = []
            for k in 0..<count {
                let t = 0.06 + 0.9 * CGFloat(k) / CGFloat(count - 1)
                let spacing = 0.9 / CGFloat(count - 1)
                let envelope = pow(sin(CGFloat.pi * min(1, t * 1.05)), 0.6)
                for (dt, isTip) in [(-spacing * 0.42, false), (0, true), (spacing * 0.42, false)] {
                    let tt = min(0.985, t + dt)
                    let b = point(tt), tg = tangent(tt)
                    let n = CGPoint(x: -tg.y * side, y: tg.x * side)
                    let base = CGPoint(x: b.x + n.x * rib, y: b.y + n.y * rib)
                    if !isTip { pts.append(base); continue }
                    let down = n.y < 0
                    let reach = L * (down ? 0.3 : 0.11) * envelope * rng.r(0.85, 1.12)
                    let gravity: CGFloat = down ? 0.75 : 0.35
                    let dir = unit(CGPoint(x: n.x * 0.55 + tg.x * 0.6, y: n.y * 0.55 + tg.y * 0.6 - gravity))
                    pts.append(CGPoint(x: base.x + dir.x * reach, y: base.y + dir.y * reach))
                }
            }
            if side > 0 { plus = pts } else { minus = pts }
        }
        let t0 = tangent(0)
        p.move(to: CGPoint(x: c.x - t0.y * rib, y: c.y + t0.x * rib))
        plus.forEach { p.addLine(to: $0) }
        p.addLine(to: tip)
        minus.reversed().forEach { p.addLine(to: $0) }
        p.addLine(to: CGPoint(x: c.x + t0.y * rib, y: c.y - t0.x * rib))
        p.closeSubpath()
    }

    // MARK: Helicopter, side view, nose to the right, in a 100 x 50 design box

    static func heliBody() -> CGPath {
        let p = CGMutablePath()
        // Cabin
        p.move(to: CGPoint(x: 52, y: 12))
        p.addLine(to: CGPoint(x: 78, y: 12))
        p.addQuadCurve(to: CGPoint(x: 91, y: 21), control: CGPoint(x: 90, y: 12))
        p.addQuadCurve(to: CGPoint(x: 74, y: 32), control: CGPoint(x: 89, y: 32))
        p.addLine(to: CGPoint(x: 57, y: 32))
        p.addQuadCurve(to: CGPoint(x: 48, y: 21), control: CGPoint(x: 48, y: 32))
        p.addQuadCurve(to: CGPoint(x: 52, y: 12), control: CGPoint(x: 48, y: 12))
        p.closeSubpath()
        // All remaining parts counter-clockwise, same as the cabin.
        poly(p, [(52, 18), (52, 27), (12, 27.6), (12, 25)])            // tail boom
        poly(p, [(10, 25), (17, 26), (9, 37), (5.5, 37)])               // tail fin
        poly(p, [(14, 23.2), (25, 23.2), (25, 25), (14, 25)])           // stabiliser
        poly(p, [(58, 30), (74, 30), (74, 33.5), (71.5, 35), (60.5, 35), (58, 33.5)]) // engine
        poly(p, [(65.5, 34), (68, 34), (68, 37.5), (65.5, 37.5)])       // mast
        return p
    }

    static func heliSkids() -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 50, y: 4))
        p.addLine(to: CGPoint(x: 84, y: 4))
        p.addQuadCurve(to: CGPoint(x: 89, y: 8), control: CGPoint(x: 88, y: 4))
        p.move(to: CGPoint(x: 58, y: 4)); p.addLine(to: CGPoint(x: 60, y: 12))
        p.move(to: CGPoint(x: 78, y: 4)); p.addLine(to: CGPoint(x: 76, y: 12))
        return p
    }

    static func heliWindow() -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 77, y: 21.5))
        p.addLine(to: CGPoint(x: 89.2, y: 21.5))
        p.addQuadCurve(to: CGPoint(x: 79, y: 29.5), control: CGPoint(x: 88, y: 29))
        p.addLine(to: CGPoint(x: 76, y: 29.5))
        p.closeSubpath()
        return p
    }

    private static func poly(_ p: CGMutablePath, _ pts: [(CGFloat, CGFloat)]) {
        p.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
        for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.0, y: q.1)) }
        p.closeSubpath()
    }

    // MARK: Bird (20 x 10), two wing poses with matching element counts for path morphing

    static func birdWingsUp() -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: 9))
        p.addQuadCurve(to: CGPoint(x: 10, y: 4), control: CGPoint(x: 6, y: 10))
        p.addQuadCurve(to: CGPoint(x: 20, y: 9), control: CGPoint(x: 14, y: 10))
        return p
    }

    static func birdWingsDown() -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 1, y: 0))
        p.addQuadCurve(to: CGPoint(x: 10, y: 4), control: CGPoint(x: 5, y: 5))
        p.addQuadCurve(to: CGPoint(x: 19, y: 0), control: CGPoint(x: 15, y: 5))
        return p
    }
}
