import AppKit

/// Night-time aircraft and birds, built from vector shapes (no game art).
enum Sprites {
    /// A helicopter in a 100 x 50 design box, scaled so it is `size` points wide.
    /// The returned layer's `transform` holds the scale and facing; animate its `position` only.
    /// `lightsOnly`: a far-off helicopter you only see as its big lights against the night.
    static func helicopter(size: CGFloat, facingRight: Bool, searchlight: CGFloat? = nil, lightsOnly: Bool = false,
                           scale: CGFloat) -> CALayer {
        let s = size / 100
        // Keep rim lines and lights a constant size on screen, however small the helicopter is.
        let rim = max(0.9, 0.8 / s)
        let rasterScale = scale * max(1, s)
        let container = CALayer()
        container.bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
        container.transform = CATransform3DMakeScale(facingRight ? s : -s, s, 1)

        let bob = CALayer()
        bob.frame = container.bounds
        container.addSublayer(bob)
        let pitch = CALayer()
        pitch.frame = bob.bounds
        pitch.setAffineTransform(CGAffineTransform(rotationAngle: -0.06))
        bob.addSublayer(pitch)

        if let length = searchlight {
            pitch.addSublayer(searchBeam(length: length / s, at: CGPoint(x: 80, y: 10)))
        }

        let rotorDisc = CAShapeLayer()
        rotorDisc.path = CGPath(ellipseIn: CGRect(x: 18, y: 34.8, width: 98, height: 4.4), transform: nil)
        rotorDisc.fillColor = Palette.c(Palette.lavender, 0.16)
        rotorDisc.contentsScale = rasterScale
        pitch.addSublayer(rotorDisc)

        // The hull (body, skids, cockpit) never changes shape, so it's rasterised once;
        // moving it then costs no more than moving a bitmap.
        let hull = CALayer()
        hull.frame = pitch.bounds
        pitch.addSublayer(hull)

        // Moonlit body: lighter slate on top, near-black underneath, so the shape reads
        // against both the night sky and dark app windows.
        let bodyPath = Shapes.heliBody()
        let bodyMask = CAShapeLayer()
        bodyMask.frame = hull.bounds
        bodyMask.path = bodyPath
        let body = CAGradientLayer()
        body.frame = hull.bounds
        body.colors = [Palette.c(0x14152a), Palette.c(0x2c3150), Palette.c(0x646b93)]
        body.locations = [0, 0.45, 0.8]
        body.startPoint = CGPoint(x: 0.5, y: 0.2)
        body.endPoint = CGPoint(x: 0.5, y: 0.75)
        body.mask = bodyMask
        hull.addSublayer(body)

        // Thin rim of moonlight on the outline.
        let edge = CAShapeLayer()
        edge.path = bodyPath
        edge.fillColor = nil
        edge.strokeColor = Palette.c(0xc9c4ee, 0.55)
        edge.lineWidth = rim
        edge.lineJoin = .round
        hull.addSublayer(edge)

        let skids = CAShapeLayer()
        skids.path = Shapes.heliSkids()
        skids.strokeColor = Palette.c(0x3d4262)
        skids.fillColor = nil
        skids.lineWidth = max(1.8, 1.2 / s)
        skids.lineCap = .round
        hull.addSublayer(skids)

        let window = CAShapeLayer()
        window.path = Shapes.heliWindow()
        window.fillColor = Palette.c(Palette.warmWindow, 0.85)
        window.shadowColor = Palette.c(Palette.warmWindow)
        window.shadowRadius = 2.5 / s
        window.shadowOpacity = 0.9
        window.shadowOffset = .zero
        hull.addSublayer(window)

        if lightsOnly { hull.opacity = 0.18 }
        hull.shouldRasterize = true
        hull.rasterizationScale = scale * max(s, 0.25)

        // Main rotor: a blade that flickers like it's spinning.
        let rotor = CAShapeLayer()
        rotor.frame = CGRect(x: 18, y: 35.5, width: 98, height: 3)
        rotor.path = CGPath(roundedRect: CGRect(x: 0, y: 0.8, width: 98, height: 1.4), cornerWidth: 0.7, cornerHeight: 0.7, transform: nil)
        rotor.fillColor = Palette.c(0x8a8fb3, 0.9)
        rotor.strokeColor = Palette.c(0xc9c4ee, 0.4)
        rotor.lineWidth = 0.5
        rotor.contentsScale = rasterScale
        let flick = CAKeyframeAnimation(keyPath: "transform.scale.x")
        flick.values = [1, 0.1, 1]
        flick.duration = 0.12
        flick.repeatCount = .infinity
        rotor.add(Anim.randomPhase(flick), forKey: "spin")
        pitch.addSublayer(rotor)

        let tailDisc = CAShapeLayer()
        tailDisc.path = CGPath(ellipseIn: CGRect(x: 3, y: 24.5, width: 12, height: 12), transform: nil)
        tailDisc.fillColor = Palette.c(Palette.lavender, 0.15)
        tailDisc.contentsScale = rasterScale
        pitch.addSublayer(tailDisc)
        let tailBlade = CAShapeLayer()
        tailBlade.frame = CGRect(x: 3, y: 24.5, width: 12, height: 12)
        tailBlade.path = CGPath(rect: CGRect(x: 5.3, y: 0.5, width: 1.4, height: 11), transform: nil)
        tailBlade.fillColor = Palette.c(0x8a8fb3, 0.9)
        tailBlade.contentsScale = rasterScale
        let tailSpin = CABasicAnimation(keyPath: "transform.rotation.z")
        tailSpin.fromValue = 0
        tailSpin.toValue = 2 * CGFloat.pi
        tailSpin.duration = 0.14
        tailSpin.repeatCount = .infinity
        tailBlade.add(tailSpin, forKey: "spin")
        pitch.addSublayer(tailBlade)

        // Lights stay at least ~1.4pt on screen so tiny, distant helicopters still read as blinking dots.
        let lr = max(2.4, 2.4 / s) * (lightsOnly ? 1.3 : 1)
        if lightsOnly {
            rotor.isHidden = true
            rotorDisc.isHidden = true
            tailDisc.isHidden = true
            tailBlade.isHidden = true
        }
        // Forward landing light: a bright lamp under the nose with a short soft cone ahead of it.
        if searchlight == nil {
            pitch.addSublayer(landingLight(at: CGPoint(x: 88, y: 12), s: s))
        }
        // Anti-collision lights with halos, so the helicopter announces itself across the screen.
        // light() gives its blink a random phase; the halo is added after with the same
        // (now phased) animation so the pair flashes in sync, then slipped beneath the lamp.
        let beaconAnim = beacon(), strobeAnim = strobe()
        let topBeacon = light(0xff3b3b, at: CGPoint(x: 67, y: 32), radius: lr, blink: beaconAnim)
        pitch.addSublayer(topBeacon)
        pitch.insertSublayer(halo(0xff3b3b, at: CGPoint(x: 67, y: 32), radius: (lightsOnly ? 22 : 14) / s, blink: beaconAnim), below: topBeacon)
        pitch.addSublayer(light(0xff3b3b, at: CGPoint(x: 6.5, y: 37), radius: lr * 0.9, blink: beacon()))
        let bellyStrobe = light(0xffffff, at: CGPoint(x: 68, y: 11), radius: lr, blink: strobeAnim)
        pitch.addSublayer(bellyStrobe)
        pitch.insertSublayer(halo(0xffffff, at: CGPoint(x: 68, y: 11), radius: (lightsOnly ? 30 : 20) / s, blink: strobeAnim), below: bellyStrobe)
        pitch.addSublayer(light(0x3dff9a, at: CGPoint(x: 86, y: 16), radius: lr * 0.7, blink: nil))

        let hover = CABasicAnimation(keyPath: "position.y")
        hover.fromValue = bob.position.y - 1.2
        hover.toValue = bob.position.y + 1.2
        hover.duration = 2.2
        hover.autoreverses = true
        hover.repeatCount = .infinity
        hover.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        bob.add(Anim.randomPhase(hover), forKey: "hover")
        return container
    }

    /// Rotates the helicopter's nose up/down along with a flight path (keyframes in radians).
    static func setPitch(_ heli: CALayer, values: [CGFloat], keyTimes: [Double], duration: Double) {
        guard let pitch = heli.sublayers?.first?.sublayers?.first else { return }
        let a = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        a.values = values
        a.keyTimes = keyTimes.map { NSNumber(value: $0) }
        a.duration = duration
        a.fillMode = .forwards
        a.isRemovedOnCompletion = false
        pitch.add(a, forKey: "pitch")
    }

    private static func searchBeam(length: CGFloat, at origin: CGPoint) -> CALayer {
        let width = length * 0.4
        let beam = CAGradientLayer()
        beam.bounds = CGRect(x: 0, y: 0, width: width, height: length)
        beam.anchorPoint = CGPoint(x: 0.5, y: 1)
        beam.position = origin
        beam.colors = [Palette.c(0xf4f0ff, 0), Palette.c(0xf4f0ff, 0.10), Palette.c(0xf4f0ff, 0.34)]
        beam.locations = [0, 0.55, 1]
        beam.startPoint = CGPoint(x: 0.5, y: 0)
        beam.endPoint = CGPoint(x: 0.5, y: 1)
        let mask = CAShapeLayer()
        mask.frame = beam.bounds
        let p = CGMutablePath()
        p.move(to: CGPoint(x: width / 2 - 1.5, y: length))
        p.addLine(to: CGPoint(x: width / 2 + 1.5, y: length))
        p.addLine(to: CGPoint(x: width, y: 0))
        p.addLine(to: CGPoint(x: 0, y: 0))
        p.closeSubpath()
        mask.path = p
        beam.mask = mask
        let sweep = CABasicAnimation(keyPath: "transform.rotation.z")
        sweep.fromValue = -0.5
        sweep.toValue = 0.25
        sweep.duration = Double.random(in: 3.5...5)
        sweep.autoreverses = true
        sweep.repeatCount = .infinity
        sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        beam.add(Anim.randomPhase(sweep), forKey: "sweep")
        return beam
    }

    /// A soft radial halo around a light, sharing the light's blink so they flash together.
    private static func halo(_ color: UInt32, at p: CGPoint, radius r: CGFloat, blink: CAAnimation) -> CALayer {
        let l = CALayer()
        l.bounds = CGRect(x: 0, y: 0, width: r * 2, height: r * 2)
        l.position = p
        l.contents = radialImage(color)
        l.add(blink, forKey: "blink")
        return l
    }

    private static func landingLight(at p: CGPoint, s: CGFloat) -> CALayer {
        let group = CALayer()
        let coneLength = 60 / s, coneWidth = 18 / s
        let cone = CAGradientLayer()
        cone.bounds = CGRect(x: 0, y: 0, width: coneLength, height: coneWidth)
        cone.anchorPoint = CGPoint(x: 0, y: 0.5)
        cone.position = p
        cone.colors = [Palette.c(0xfff6e0, 0.45), Palette.c(0xfff6e0, 0.12), Palette.c(0xfff6e0, 0)]
        cone.locations = [0, 0.4, 1]
        cone.startPoint = CGPoint(x: 0, y: 0.5)
        cone.endPoint = CGPoint(x: 1, y: 0.5)
        let mask = CAShapeLayer()
        mask.frame = cone.bounds
        let m = CGMutablePath()
        m.move(to: CGPoint(x: 0, y: coneWidth / 2 - 1.5 / s))
        m.addLine(to: CGPoint(x: coneLength, y: 0))
        m.addLine(to: CGPoint(x: coneLength, y: coneWidth))
        m.addLine(to: CGPoint(x: 0, y: coneWidth / 2 + 1.5 / s))
        m.closeSubpath()
        mask.path = m
        cone.mask = mask
        cone.setAffineTransform(CGAffineTransform(rotationAngle: -0.25))   // angled down ahead
        group.addSublayer(cone)
        group.addSublayer(light(0xfff6e0, at: p, radius: max(1.4, 1.3 / s), blink: nil))
        return group
    }

    nonisolated(unsafe) private static var radialCache: [UInt32: CGImage] = [:]
    private static func radialImage(_ color: UInt32) -> CGImage? {
        if let cached = radialCache[color] { return cached }
        let size = 64
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                           colors: [Palette.c(color, 0.75), Palette.c(color, 0.22), Palette.c(color, 0)] as CFArray,
                           locations: [0, 0.35, 1])!
        let c = CGPoint(x: 32, y: 32)
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: 32, options: [])
        let image = ctx.makeImage()
        radialCache[color] = image
        return image
    }

    private static func light(_ color: UInt32, at p: CGPoint, radius r: CGFloat, blink: CAAnimation?) -> CALayer {
        let l = CALayer()
        l.bounds = CGRect(x: 0, y: 0, width: r * 2, height: r * 2)
        l.cornerRadius = r
        l.position = p
        l.backgroundColor = Palette.c(color)
        l.shadowColor = Palette.c(color)
        l.shadowRadius = r * 1.6
        l.shadowOpacity = 1
        l.shadowOffset = .zero
        if let blink { l.add(Anim.randomPhase(blink), forKey: "blink") }
        return l
    }

    private static func beacon() -> CAAnimation {
        let a = CAKeyframeAnimation(keyPath: "opacity")
        a.values = [1, 1, 0.05, 0.05]
        a.keyTimes = [0, 0.18, 0.24, 1]
        a.duration = 1.3
        a.repeatCount = .infinity
        return a
    }

    private static func strobe() -> CAAnimation {
        let a = CAKeyframeAnimation(keyPath: "opacity")
        a.values = [0, 1, 0, 1, 0, 0]
        a.keyTimes = [0, 0.03, 0.08, 0.13, 0.18, 1]
        a.duration = 1.9
        a.repeatCount = .infinity
        return a
    }

    /// A high-altitude jet: just its blinking lights crossing the sky.
    static func jet() -> CALayer {
        let c = CALayer()
        c.bounds = CGRect(x: 0, y: 0, width: 8, height: 4)
        c.addSublayer(light(0xffffff, at: CGPoint(x: 4, y: 2), radius: 0.9, blink: nil))
        c.sublayers?.first?.opacity = 0.7
        c.addSublayer(light(0xff3b3b, at: CGPoint(x: 1, y: 2), radius: 1.0, blink: beacon()))
        c.addSublayer(light(0xffffff, at: CGPoint(x: 7, y: 2), radius: 1.0, blink: strobe()))
        return c
    }

    static func bird(size: CGFloat, scale: CGFloat) -> CALayer {
        let s = size / 20
        let l = CAShapeLayer()
        l.bounds = CGRect(x: 0, y: 0, width: 20, height: 10)
        l.transform = CATransform3DMakeScale(s, s, 1)
        l.path = Shapes.birdWingsUp()
        l.strokeColor = Palette.c(Palette.birdSlate, 0.95)
        l.fillColor = nil
        l.lineWidth = 1.7
        l.lineCap = .round
        l.lineJoin = .round
        l.contentsScale = scale * max(1, s)
        let flap = CABasicAnimation(keyPath: "path")
        flap.fromValue = Shapes.birdWingsUp()
        flap.toValue = Shapes.birdWingsDown()
        flap.duration = Double.random(in: 0.28...0.38)
        flap.autoreverses = true
        flap.repeatCount = .infinity
        flap.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        l.add(Anim.randomPhase(flap), forKey: "flap")
        return l
    }
}
