import AppKit

final class SkyView: LayerHostView {
    let screenFrame: CGRect
    let scale: CGFloat
    init(screen: NSScreen) {
        screenFrame = screen.frame
        scale = screen.backingScaleFactor
        super.init(size: screen.frame.size)
    }
}

/// Schedules helicopters, searchlights, jets and birds across the sky windows.
@MainActor
final class TrafficDirector {
    enum Event: CaseIterable { case farHeli, heli, closeHeli, searchHeli, jet, birds }

    var skies: [SkyView] = []
    /// Dock frame in global (Cocoa) coordinates, if the Dock is visible at the bottom of a screen.
    var dockFrame: () -> CGRect? = { nil }
    private var timer: Timer?

    func start() {
        schedule(after: 4)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        skies = []
    }

    func rescheduleForTrafficChange() {
        guard timer != nil else { return }
        schedule(after: 2)
    }

    private func schedule(after seconds: Double? = nil) {
        timer?.invalidate()
        let gap = seconds ?? Double.random(in: Settings.shared.traffic.gap)
        timer = Timer.scheduledTimer(withTimeInterval: gap, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.spawnRandom()
                self?.schedule()
            }
        }
    }

    private func spawnRandom() {
        let s = Settings.shared
        var options: [(Event, Double)] = []
        if s.isOn(.helicopters) {
            // Mostly the searchlight helicopter; plain ones are small and far away.
            if s.isOn(.searchlights) { options.append((.searchHeli, 30)) }
            options += [(.heli, 10)]
        }
        if s.isOn(.jets) { options.append((.jet, 20)) }
        if s.isOn(.birds) { options.append((.birds, 8)) }
        let total = options.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return }
        var roll = Double.random(in: 0..<total)
        for (event, weight) in options {
            if roll < weight { spawn(event); return }
            roll -= weight
        }
    }

    /// "Summon a helicopter" from the menu.
    func summon() {
        spawn(.searchHeli)
    }

    func spawn(_ event: Event) {
        guard let sky = pickSky() else { return }
        let H = sky.bounds.height
        let fromLeft = Bool.random()
        switch event {
        case .farHeli:
            spawn(.heli)   // tiny far-off helicopters were dropped; they read as specks
        case .heli:
            let size = CGFloat.random(in: 36...46)
            let heli = Sprites.helicopter(size: size, facingRight: fromLeft, scale: sky.scale)
            fly(heli, in: sky, fromLeft: fromLeft, y: H * .random(in: 0.5...0.85), margin: size, duration: .random(in: 26...38))
        case .closeHeli:
            spawn(.heli)
        case .searchHeli:
            let size = CGFloat.random(in: 38...48)
            let heli = Sprites.helicopter(size: size, facingRight: fromLeft, searchlight: H * 0.4, scale: sky.scale)
            fly(heli, in: sky, fromLeft: fromLeft, y: H * .random(in: 0.66...0.88), margin: H * 0.25, duration: .random(in: 38...55))
        case .jet:
            let jet = Sprites.jet()
            fly(jet, in: sky, fromLeft: fromLeft, y: H * .random(in: 0.8...0.95), margin: 20, duration: .random(in: 70...100), curve: 0.01)
        case .birds:
            // Usually a lone gull, sometimes two that don't fly in lockstep.
            let count = Double.random(in: 0..<1) < 0.7 ? 1 : 2
            for i in 0..<count {
                let bird = Sprites.bird(size: .random(in: 9...14), scale: sky.scale)
                let dir = i == 0 ? fromLeft : (Double.random(in: 0..<1) < 0.8 ? fromLeft : !fromLeft)
                fly(bird, in: sky, fromLeft: dir, y: H * .random(in: 0.45...0.85), margin: 30,
                    duration: .random(in: 22...40), curve: 0.12, delay: Double(i) * .random(in: 2...9))
            }
        }
    }

    private func pickSky() -> SkyView? {
        guard !skies.isEmpty else { return nil }
        let main = skies.first { $0.screenFrame == NSScreen.main?.frame }
        if let main, skies.count > 1, Double.random(in: 0..<1) < 0.5 { return main }
        return skies.randomElement()
    }

    private func fly(_ layer: CALayer, in sky: SkyView, fromLeft: Bool, y: CGFloat, margin: CGFloat,
                     duration: Double, curve: CGFloat = 0.08, seed: UInt64? = nil, delay: Double = 0) {
        let W = sky.bounds.width, H = sky.bounds.height
        let x0 = fromLeft ? -margin : W + margin
        let x1 = fromLeft ? W + margin : -margin
        var rng = RNG(seed ?? UInt64.random(in: 0...UInt64.max))
        let y1 = y + H * rng.r(-curve, curve)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x0, y: y))
        path.addQuadCurve(to: CGPoint(x: x1, y: y1), control: CGPoint(x: (x0 + x1) / 2, y: (y + y1) / 2 + H * rng.r(-curve, curve)))
        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path
        move.duration = duration
        move.calculationMode = .paced
        move.fillMode = .both
        move.isRemovedOnCompletion = false
        if delay > 0 { move.beginTime = CACurrentMediaTime() + delay }
        run(layer, in: sky, start: CGPoint(x: x0, y: y), animation: move, duration: duration + delay)
    }

    private func run(_ layer: CALayer, in sky: SkyView, start: CGPoint, animation: CAAnimation, duration: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.position = start
        sky.root.addSublayer(layer)
        layer.add(animation, forKey: "flight")
        CATransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.5) { [weak layer] in
            layer?.removeFromSuperlayer()
        }
    }
}
