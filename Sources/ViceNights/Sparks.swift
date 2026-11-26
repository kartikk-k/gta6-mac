import AppKit

/// Little starburst sparks that pop up at random spots and random intervals, sometimes alone,
/// sometimes as a quick cluster, then shrink away. They share the sky windows, so they follow
/// the Sky → Fly Over Windows setting.
@MainActor
final class SparkDirector {
    var views: [SkyView] = []
    private var timer: Timer?

    func start() {
        schedule(after: .random(in: 1...3))
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        views = []
    }

    private func schedule(after seconds: Double) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.burst()
                // Irregular rhythm: mostly short gaps, now and then a longer pause.
                let gap = Double.random(in: 0..<1) < 0.8 ? Double.random(in: 0.6...3.5) : Double.random(in: 5...10)
                self.schedule(after: gap)
            }
        }
    }

    private func burst() {
        guard Settings.shared.isOn(.sparks), !Anim.reduceMotion, let view = views.randomElement() else { return }
        let W = view.bounds.width, H = view.bounds.height
        // Keep sparks to the outer parts of the screen, away from the middle where you work.
        var center = CGPoint.zero
        repeat {
            center = CGPoint(x: .random(in: W * 0.03...W * 0.97), y: .random(in: H * 0.08...H * 0.95))
        } while center.x > W * 0.22 && center.x < W * 0.78 && center.y > H * 0.2 && center.y < H * 0.85
        let count = Double.random(in: 0..<1) < 0.65 ? 1 : Int.random(in: 2...4)
        for i in 0..<count {
            let offset = i == 0 ? CGPoint.zero : CGPoint(x: .random(in: -70...70), y: .random(in: -50...50))
            spark(in: view, at: CGPoint(x: center.x + offset.x, y: center.y + offset.y),
                  delay: Double(i) * .random(in: 0.08...0.3))
        }
    }

    private func spark(in view: SkyView, at p: CGPoint, delay: Double) {
        let colors: [UInt32] = [0xffffff, 0xf3ebff, Palette.neonPink, Palette.neonCyan, Palette.neonViolet, Palette.warmWindow]
        let radius = CGFloat.random(in: 7...16)
        let s = Flare.starburst(radius: radius, color: colors.randomElement()!, spokes: Int.random(in: 2...3),
                                thickness: radius > 12 ? 1.3 : 1.0, animate: false)
        s.position = p
        s.opacity = 0
        let duration = Double.random(in: 0.6...1.3)

        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
        pop.values = [0.15, 1.15, 0.9, 0.2]
        pop.keyTimes = [0, 0.25, 0.6, 1]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 0.85, 0]
        fade.keyTimes = [0, 0.18, 0.6, 1]
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = CGFloat.random(in: -0.6...0.6)
        let group = CAAnimationGroup()
        group.animations = [pop, fade, spin]
        group.duration = duration
        group.beginTime = CACurrentMediaTime() + delay
        group.fillMode = .both
        group.isRemovedOnCompletion = false
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.root.addSublayer(s)
        s.add(Anim.throttle(group, fps: 60), forKey: "spark")
        CATransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + duration + 0.2) { [weak s] in
            s?.removeFromSuperlayer()
        }
    }
}
