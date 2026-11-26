import AppKit

/// Full-screen layer that sits on top of the real wallpaper (which is never touched).
final class BackdropView: LayerHostView {
    private let scale: CGFloat
    private let base = CAGradientLayer()
    private let photoHost = CALayer()
    private var photoLayer: CALayer?
    private var skyline: CALayer?
    private let tint = CALayer()
    private let vignette = CAGradientLayer()
    private let gradeTop = CAGradientLayer()
    private let gradeBottom = CAGradientLayer()
    private let beams = CALayer()
    private let dreamy = DreamyLightsLayer()
    private(set) var showingSkyline = false

    init(size: CGSize, scale: CGFloat) {
        self.scale = scale
        super.init(size: size)
        root.backgroundColor = Palette.c(Palette.siteNavyBottom)

        // The site's own background: a barely-there navy gradient.
        base.frame = bounds
        base.colors = [Palette.c(Palette.siteNavyBottom), Palette.c(Palette.siteNavyTop)]
        base.startPoint = CGPoint(x: 0.5, y: 0)
        base.endPoint = CGPoint(x: 0.5, y: 1)
        root.addSublayer(base)

        photoHost.frame = bounds
        photoHost.masksToBounds = true
        root.addSublayer(photoHost)

        // "Vice grade": pull every photo toward the site's violet / navy palette.
        tint.frame = bounds
        tint.backgroundColor = Palette.c(Palette.skyViolet, 0.45)
        tint.compositingFilter = CIFilter(name: "CISoftLightBlendMode")
        root.addSublayer(tint)

        vignette.frame = bounds
        vignette.type = .radial
        vignette.colors = [Palette.c(Palette.siteNavyBottom, 0), Palette.c(Palette.siteNavyBottom, 0.55)]
        vignette.locations = [0.6, 1]
        vignette.startPoint = CGPoint(x: 0.5, y: 0.5)
        vignette.endPoint = CGPoint(x: 1.05, y: 1.1)
        root.addSublayer(vignette)

        // Darken under the menu bar and above the Dock so both stay legible.
        gradeTop.frame = CGRect(x: 0, y: bounds.height * 0.84, width: bounds.width, height: bounds.height * 0.16)
        gradeTop.colors = [Palette.c(Palette.siteNavyBottom, 0), Palette.c(Palette.siteNavyBottom, 0.6)]
        root.addSublayer(gradeTop)
        gradeBottom.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height * 0.2)
        gradeBottom.colors = [Palette.c(Palette.siteNavyBottom, 0.65), Palette.c(Palette.siteNavyBottom, 0)]
        root.addSublayer(gradeBottom)

        dreamy.setup(size: bounds.size)
        root.addSublayer(dreamy)

        beams.frame = bounds
        root.addSublayer(beams)
        updateEffects()
    }

    // MARK: Content

    /// Extra size the photo is decoded at, so the slow drift ends at 1:1 pixels (pin-sharp).
    static let overscan: CGFloat = 1.06

    func showPhoto(_ image: CGImage, holdFor seconds: TimeInterval) {
        let o = Self.overscan
        let l = CALayer()
        l.bounds = CGRect(x: 0, y: 0, width: bounds.width * o, height: bounds.height * o)
        l.position = CGPoint(x: bounds.midX, y: bounds.midY)
        l.contents = image
        l.contentsGravity = .resize
        l.contentsScale = scale
        l.opacity = 0
        let drift = Settings.shared.isOn(.drift) && !Anim.reduceMotion
        // Without drift, sit at 1:1 (edges cropped by the 6% overscan).
        l.transform = drift ? CATransform3DMakeScale(1 / o, 1 / o, 1) : CATransform3DIdentity
        photoHost.addSublayer(l)
        Anim.fade(l, to: 1, duration: 2.5)
        if let old = photoLayer {
            Anim.fade(old, to: 0, duration: 2.5) {
                old.removeFromSuperlayer()
                old.contents = nil   // release the decoded bitmap right away
            }
        }
        photoLayer = l
        if drift { kenBurns(l, duration: seconds > 0 ? seconds + 5 : 600) }
        placeFlares(on: image)
        if let s = skyline {
            // Drop the generated scene entirely (its bitmaps and live animations) once hidden.
            skyline = nil
            Anim.fade(s, to: 0, duration: 2.5) { s.removeFromSuperlayer() }
        }
        showingSkyline = false
        updateEffects()
    }

    func showSkyline() {
        if skyline == nil {
            let s = SkylineScene.build(size: bounds.size, scale: scale)
            s.opacity = 0
            root.insertSublayer(s, above: photoHost)
            skyline = s
        }
        if let s = skyline { Anim.fade(s, to: 1, duration: 2.0) }
        if let old = photoLayer {
            Anim.fade(old, to: 0, duration: 2.0) { old.removeFromSuperlayer() }
            photoLayer = nil
        }
        showingSkyline = true
        dreamy.showFlares(at: [(CGPoint(x: bounds.width * 0.5, y: bounds.height * 0.62), 0.8),
                               (CGPoint(x: bounds.width * 0.22, y: bounds.height * 0.42), 0.5),
                               (CGPoint(x: bounds.width * 0.78, y: bounds.height * 0.83), 0.6)])
        updateEffects()
    }

    var hasContent: Bool { photoLayer != nil || showingSkyline }

    /// Put starburst flares on the photo's brightest point lights (street lamps, signs).
    private func placeFlares(on image: CGImage) {
        let size = bounds.size, o = Self.overscan
        Task { @MainActor in
            let found = await Task.detached(priority: .utility) { LightFinder.find(in: image, maxCount: 40) }.value
            // The photo is centred and `overscan` larger than the screen.
            let points = found.compactMap { (p, strength) -> (CGPoint, CGFloat)? in
                let v = CGPoint(x: size.width / 2 + (p.x - 0.5) * size.width * o,
                                y: size.height / 2 + (p.y - 0.5) * size.height * o)
                guard v.x > 0, v.x < size.width, v.y > 0, v.y < size.height else { return nil }
                // Keep big flares out of the middle, where your windows are.
                let inMiddle = v.x > size.width * 0.18 && v.x < size.width * 0.82 && v.y > size.height * 0.15 && v.y < size.height * 0.85
                guard !inMiddle else { return nil }
                return (v, strength)
            }
            self.dreamy.showFlares(at: points)
        }
    }

    /// Slow push-in from "whole image" to exactly one image pixel per screen pixel.
    private func kenBurns(_ l: CALayer, duration: TimeInterval) {
        let o = Self.overscan
        let slack = (o - 1) / 2
        let dx = CGFloat.random(in: -slack...slack) * bounds.width * 0.8
        let dy = CGFloat.random(in: -slack...slack) * bounds.height * 0.8
        let a = CABasicAnimation(keyPath: "transform")
        a.fromValue = CATransform3DMakeScale(1 / o, 1 / o, 1)
        a.toValue = CATransform3DMakeTranslation(dx, dy, 0)
        a.duration = duration
        a.fillMode = .forwards
        a.isRemovedOnCompletion = false
        a.timingFunction = CAMediaTimingFunction(name: .easeOut)
        l.add(Anim.throttle(a, fps: 10), forKey: "kenBurns")
    }

    // MARK: Effects

    func updateEffects() {
        let s = Settings.shared
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let grade = s.isOn(.viceGrade)
        tint.isHidden = !grade || showingSkyline
        vignette.isHidden = !grade
        gradeTop.isHidden = !grade
        gradeBottom.isHidden = !grade
        // When the lights are set to play over apps they live in their own window instead.
        let wantBeams = s.isOn(.clubBeams) && !s.isOn(.partyOverApps) && !Anim.reduceMotion
        dreamy.isHidden = !s.isOn(.dreamyLights)
        if wantBeams && (beams.sublayers ?? []).isEmpty { PartyLights.build(in: beams, size: bounds.size, additive: true) }
        beams.isHidden = !wantBeams
        CATransaction.commit()
    }

}

/// Picks official images, downloads them on demand and rotates them on every display.
@MainActor
final class WallpaperDirector {
    var views: [BackdropView] = []
    private(set) var current: Shot?
    private(set) var status = ""
    private var timer: Timer?
    private var position: [WallpaperSet: Int] = [:]
    private var token = UUID()

    func start() {
        show(advance: false)
        scheduleTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        token = UUID()
        views = []
    }

    func scheduleTimer() {
        timer?.invalidate()
        timer = nil
        let minutes = Settings.shared.rotateMinutes
        guard minutes > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Double(minutes) * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.show(advance: true) }
        }
    }

    /// Re-decode the current wallpaper (after a setting that's baked into the image changes).
    func reload() { show(advance: false) }

    func next() {
        show(advance: true)
        scheduleTimer()
    }

    private func show(advance: Bool) {
        let set = Settings.shared.wallpaperSet
        let list = Catalog.shots(for: set)
        let myToken = UUID()
        token = myToken
        guard !list.isEmpty else {
            current = nil
            status = "Neon Skyline"
            views.forEach { $0.showSkyline() }
            return
        }
        var start = position[set] ?? 0
        if advance { start = (start + 1) % list.count }

        // First run: show the generated skyline while the first official image downloads.
        if !ImageStore.shared.isCached(list[start]) {
            status = "Downloading from rockstargames.com…"
            views.filter { !$0.hasContent }.forEach { $0.showSkyline() }
        }
        let hold = Double(Settings.shared.rotateMinutes) * 60
        let fringe = Settings.shared.isOn(.lensFringe)
        let targets = views.map { v -> (BackdropView, CGSize) in
            let sf = v.window?.backingScaleFactor ?? 2
            return (v, CGSize(width: v.bounds.width * sf, height: v.bounds.height * sf))
        }

        Task { @MainActor in
            for attempt in 0..<list.count {
                let index = (start + attempt) % list.count
                let shot = list[index]
                guard let url = await ImageStore.shared.ensure(shot) else { continue }
                guard self.token == myToken else { return }
                var shown = false
                // One decode per display (they may differ in size); each is released on the next change.
                for (view, pixels) in targets {
                    let overscan = BackdropView.overscan
                    let image = await Task.detached(priority: .userInitiated) {
                        ImageStore.decodeForDisplay(url, pixelSize: pixels, overscan: overscan, viceTint: false, fringe: fringe)
                    }.value
                    guard self.token == myToken else { return }
                    guard let image else { continue }
                    view.showPhoto(image, holdFor: hold)
                    shown = true
                }
                guard shown else { continue }
                self.position[set] = index
                self.current = shot
                self.status = shot.title
                let upcoming = list[(index + 1) % list.count]
                Task { _ = await ImageStore.shared.ensure(upcoming) }
                return
            }
            guard self.token == myToken else { return }
            self.status = "Offline: showing Neon Skyline"
            self.views.forEach { $0.showSkyline() }
        }
    }
}
