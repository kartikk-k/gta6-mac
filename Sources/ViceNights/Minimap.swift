import AppKit

extension NSWindow.Level {
    /// The minimap sits on the desktop, above the corner palms but under every app window.
    static let minimap = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 3)
}

/// A game-style GPS minimap in the bottom-left corner, on frosted glass like the Dock.
///
/// Your real screen is drawn as a city: open windows are the lit blocks, with a street grid and a
/// multi-lane highway running through them. The pointer is the player arrow, the front window is
/// the pink waypoint, and a pink GPS route runs along the streets from the player (parked on an
/// avenue near the bottom, like the game's arrow) to it, with a "Turn Left · 121 ft" card above the
/// map. It ignores the mouse: it only changes when windows open, close, move or come to the front. Window positions come from the window list, which needs
/// no permissions (no titles or contents are read). It refreshes a few times a second, and not at
/// all while it's covered.
@MainActor
final class MinimapDirector {
    private var windows: [OverlayWindow] = []
    private var views: [MinimapView] = []
    private var timer: Timer?

    func start() {
        stop()
        guard Settings.shared.isOn(.themeOn), Settings.shared.isOn(.minimap) else { return }
        for screen in NSScreen.screens {
            let layout = MinimapView.Layout(screen: screen)
            let vf = screen.visibleFrame
            let frame = CGRect(x: vf.minX + 16, y: vf.minY + 14, width: layout.size.width, height: layout.size.height)
            let w = OverlayWindow(frame: frame, level: .minimap)
            let container = NSView(frame: CGRect(origin: .zero, size: layout.size))
            // Two frosted-glass panels, blurring the wallpaper like the Dock: directions and map.
            for (rect, radius) in [(layout.banner, MinimapView.bannerRadius), (layout.map, MinimapView.mapRadius)] {
                let glass = NSVisualEffectView(frame: rect)
                glass.material = .hudWindow
                glass.blendingMode = .behindWindow
                glass.state = .active
                glass.appearance = NSAppearance(named: .darkAqua)
                glass.maskImage = Self.roundedMask(size: rect.size, radius: radius)
                container.addSubview(glass)
            }
            let view = MinimapView(screen: screen, layout: layout)
            view.frame = container.bounds
            container.addSubview(view)
            w.contentView = container
            w.orderFrontRegardless()
            windows.append(w)
            views.append(view)
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer?.tolerance = 0.1
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        windows.forEach { $0.orderOut(nil) }
        windows = []
        views = []
    }

    private static func roundedMask(size: CGSize, radius: CGFloat) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    private func refresh() {
        // Nothing to do while every minimap is hidden behind app windows.
        let visible = zip(windows, views).filter { $0.0.occlusionState.contains(.visible) }
        guard !visible.isEmpty else { return }
        let rects = Self.appWindows()
        // Only redraw when something actually changed.
        let signature = rects.map { "\($0.id):\($0.frame.integral)" }.joined(separator: "|")
        for (_, view) in visible where view.signature != signature {
            view.signature = signature
            view.update(windows: rects)
        }
    }

    /// On-screen app windows, front to back, in global Cocoa coordinates.
    private static func appWindows() -> [(id: Int, frame: CGRect)] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]],
              let primaryHeight = NSScreen.screens.first?.frame.height else { return [] }
        let me = ProcessInfo.processInfo.processIdentifier
        var out: [(Int, CGRect)] = []
        for w in info {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? Int32) != me,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.05,
                  let id = w[kCGWindowNumber as String] as? Int,
                  let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: b),
                  r.width > 60, r.height > 40 else { continue }
            out.append((id, CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)))
        }
        return out
    }
}

final class MinimapView: LayerHostView {
    static let mapRadius: CGFloat = 14
    static let bannerRadius: CGFloat = 10

    struct Layout {
        let size: CGSize
        let map: CGRect
        let banner: CGRect
        init(screen: NSScreen) {
            let w: CGFloat = 200
            let mapH = (w * screen.frame.height / screen.frame.width).rounded()
            let bannerH: CGFloat = 36, gap: CGFloat = 6
            size = CGSize(width: w, height: mapH + gap + bannerH)
            map = CGRect(x: 0, y: 0, width: w, height: mapH)
            banner = CGRect(x: 0, y: mapH + gap, width: w, height: bannerH)
        }
    }

    // Palette, after the in-game GPS map.
    private static let land: UInt32 = 0x1f2560
    private static let block: UInt32 = 0x34459a
    private static let frontBlock: UInt32 = 0x4659bd
    private static let road: UInt32 = 0x8d89a8
    private static let routePink: UInt32 = 0xf3a2c6
    private static let dotPink: UInt32 = 0xee6aa2

    private let screenFrame: CGRect
    private let scale: CGFloat
    private let s: CGFloat                  // map points per screen point
    private let mapRect: CGRect
    private let blocks = CALayer()
    private var blockLayers: [Int: CALayer] = [:]
    private let route = CAShapeLayer()
    private let waypoint = CAShapeLayer()
    private let player = CALayer()
    private let arrow = CAShapeLayer()
    private let distance = CATextLayer()
    private let turnTitle = CATextLayer()
    private let turnDistance = CATextLayer()
    private let turnIcon = CALayer()
    private var iconName = ""
    private var verticals: [CGFloat] = []    // street x-positions, map coordinates
    private var horizontals: [CGFloat] = []  // street y-positions
    private var home = CGPoint.zero          // where the player arrow is parked
    var signature = ""                       // the window layout last drawn

    init(screen: NSScreen, layout: Layout) {
        screenFrame = screen.frame
        scale = screen.backingScaleFactor
        mapRect = layout.map
        s = layout.map.width / screen.frame.width
        super.init(size: layout.size)
        buildMap(layout.map)
        buildBanner(layout.banner)
    }

    // MARK: Map

    private func buildMap(_ rect: CGRect) {
        let W = rect.width, H = rect.height
        let card = CALayer()
        card.frame = rect
        card.cornerRadius = Self.mapRadius
        card.cornerCurve = .continuous
        card.masksToBounds = true
        card.backgroundColor = Palette.c(Self.land, 0.78)
        root.addSublayer(card)

        blocks.frame = card.bounds
        card.addSublayer(blocks)
        card.addSublayer(streets(W: W, H: H))

        // Landmarks: the Dock as a glowing strip along the bottom.
        if let screen = NSScreen.screens.first(where: { $0.frame == screenFrame }) {
            let dockH = max(0, screen.visibleFrame.minY - screen.frame.minY) * s
            if dockH > 1 {
                let dock = CALayer()
                dock.frame = CGRect(x: W * 0.05, y: 1, width: W * 0.9, height: dockH - 1.5)
                dock.cornerRadius = dockH * 0.35
                dock.backgroundColor = Palette.c(Palette.neonViolet, 0.22)
                dock.borderColor = Palette.c(Palette.neonViolet, 0.6)
                dock.borderWidth = 0.6
                card.addSublayer(dock)
            }
        }

        route.fillColor = nil
        route.strokeColor = Palette.c(Self.routePink, 0.95)
        route.lineWidth = 4.5
        route.lineCap = .round
        route.lineJoin = .round
        route.contentsScale = scale
        card.addSublayer(route)

        let r: CGFloat = 4.5
        waypoint.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r), transform: nil)
        waypoint.fillColor = Palette.c(Self.dotPink)
        waypoint.strokeColor = Palette.c(0xffffff, 0.85)
        waypoint.lineWidth = 1
        waypoint.contentsScale = scale
        waypoint.isHidden = true
        card.addSublayer(waypoint)

        // The player: a white arrow in a grey disc with a white ring.
        player.bounds = CGRect(x: -8, y: -8, width: 16, height: 16)
        let disc = CAShapeLayer()
        disc.path = CGPath(ellipseIn: CGRect(x: -6.5, y: -6.5, width: 13, height: 13), transform: nil)
        disc.fillColor = Palette.c(0x4a4858, 0.95)
        disc.strokeColor = Palette.c(0xffffff, 0.9)
        disc.lineWidth = 1.2
        disc.contentsScale = scale
        player.addSublayer(disc)
        let a = CGMutablePath()
        a.move(to: CGPoint(x: 0, y: 4.2))
        a.addLine(to: CGPoint(x: 3.1, y: -3.3))
        a.addLine(to: CGPoint(x: 0, y: -1.8))
        a.addLine(to: CGPoint(x: -3.1, y: -3.3))
        a.closeSubpath()
        arrow.path = a
        arrow.fillColor = CGColor(gray: 1, alpha: 1)
        arrow.lineJoin = .round
        arrow.contentsScale = scale
        player.addSublayer(arrow)
        // Parked on the avenue nearest the middle, on the lowest cross street.
        home = CGPoint(x: verticals.min(by: { abs($0 - W / 2) < abs($1 - W / 2) }) ?? W / 2,
                       y: horizontals.first ?? H * 0.25)
        player.position = home
        card.addSublayer(player)

        // Remaining distance, top-left.
        distance.fontSize = 11
        distance.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        distance.foregroundColor = .white
        distance.contentsScale = scale
        distance.frame = CGRect(x: 8, y: H - 18, width: 90, height: 14)
        distance.shadowColor = .black
        distance.shadowOpacity = 0.7
        distance.shadowRadius = 1.5
        distance.shadowOffset = .zero
        card.addSublayer(distance)

        // North badge on the bottom edge, like the game.
        let n = CALayer()
        n.frame = CGRect(x: W / 2 - 7, y: 2, width: 14, height: 14)
        n.cornerRadius = 7
        n.backgroundColor = Palette.c(0x0d0c12, 0.9)
        let t = CATextLayer()
        t.string = NSAttributedString(string: "N", attributes: [
            .font: NSFont.systemFont(ofSize: 8.5, weight: .heavy),
            .foregroundColor: NSColor.white,
        ])
        t.alignmentMode = .center
        t.contentsScale = scale
        t.frame = CGRect(x: 0, y: 1.8, width: 14, height: 11)
        n.addSublayer(t)
        card.addSublayer(n)

        root.addSublayer(rim(rect, radius: Self.mapRadius))
    }

    private func rim(_ rect: CGRect, radius: CGFloat) -> CALayer {
        let rim = CALayer()
        rim.frame = rect
        rim.cornerRadius = radius
        rim.cornerCurve = .continuous
        rim.borderColor = Palette.c(0xffffff, 0.28)
        rim.borderWidth = 0.8
        return rim
    }

    /// The street plan, drawn once: a grid of avenues (some wide, some narrow) and a curving
    /// multi-lane highway with lane markings. The grid is also what the GPS route follows.
    private func streets(W: CGFloat, H: CGFloat) -> CALayer {
        var rng = RNG(UInt64(screenFrame.width * 31 + screenFrame.height))
        let holder = CALayer()
        holder.frame = CGRect(x: 0, y: 0, width: W, height: H)

        var x = rng.r(14, 26)
        while x < W - 8 { verticals.append(x); x += rng.r(32, 50) }
        var y = rng.r(22, 32)
        while y < H - 10 { horizontals.append(y); y += rng.r(24, 36) }

        func stroke(_ path: CGPath, width: CGFloat, color: UInt32, alpha: CGFloat, dash: [NSNumber]? = nil) {
            let l = CAShapeLayer()
            l.path = path
            l.fillColor = nil
            l.strokeColor = Palette.c(color, alpha)
            l.lineWidth = width
            l.lineDashPattern = dash
            l.lineCap = dash == nil ? .butt : .butt
            l.contentsScale = scale
            holder.addSublayer(l)
        }

        // Narrow back streets between the avenues.
        let lanes = CGMutablePath()
        for (a, b) in zip(verticals, verticals.dropFirst()) where rng.r(0, 1) < 0.7 {
            let mid = (a + b) / 2 + rng.r(-4, 4)
            lanes.move(to: CGPoint(x: mid, y: 0)); lanes.addLine(to: CGPoint(x: mid, y: H))
        }
        for (a, b) in zip(horizontals, horizontals.dropFirst()) where rng.r(0, 1) < 0.6 {
            let mid = (a + b) / 2 + rng.r(-3, 3)
            lanes.move(to: CGPoint(x: 0, y: mid)); lanes.addLine(to: CGPoint(x: W, y: mid))
        }
        stroke(lanes, width: 1.6, color: Self.road, alpha: 0.35)

        // Avenues.
        let main = CGMutablePath(), wide = CGMutablePath()
        for (i, vx) in verticals.enumerated() {
            let p = i % 2 == 0 ? wide : main
            p.move(to: CGPoint(x: vx, y: 0)); p.addLine(to: CGPoint(x: vx, y: H))
        }
        for (i, hy) in horizontals.enumerated() {
            let p = i % 2 == 1 ? wide : main
            p.move(to: CGPoint(x: 0, y: hy)); p.addLine(to: CGPoint(x: W, y: hy))
        }
        stroke(main, width: 4, color: Self.road, alpha: 0.75)
        stroke(wide, width: 6.5, color: Self.road, alpha: 0.85)

        // The highway: a wide sweep with a darker median and dashed lane lines.
        let hw = CGMutablePath()
        hw.move(to: CGPoint(x: -10, y: H * rng.r(0.25, 0.4)))
        hw.addCurve(to: CGPoint(x: W + 10, y: H * rng.r(0.7, 0.9)),
                    control1: CGPoint(x: W * 0.4, y: H * rng.r(0.2, 0.35)),
                    control2: CGPoint(x: W * 0.55, y: H * rng.r(0.8, 1.0)))
        stroke(hw, width: 14, color: 0x6c6888, alpha: 0.95)
        stroke(hw, width: 11, color: Self.road, alpha: 0.95)
        stroke(hw, width: 1, color: 0x55526e, alpha: 0.9)
        stroke(hw, width: 6, color: 0xffffff, alpha: 0.35, dash: [3, 4])
        stroke(hw, width: 5, color: Self.road, alpha: 1)

        holder.shouldRasterize = true
        holder.rasterizationScale = scale
        return holder
    }

    // MARK: Directions banner

    private func buildBanner(_ rect: CGRect) {
        let card = CALayer()
        card.frame = rect
        card.cornerRadius = Self.bannerRadius
        card.cornerCurve = .continuous
        card.masksToBounds = true
        card.backgroundColor = Palette.c(0x1d1f3d, 0.62)
        root.addSublayer(card)

        let iconW: CGFloat = 38
        let pink = CALayer()
        pink.frame = CGRect(x: rect.width - iconW, y: 0, width: iconW, height: rect.height)
        pink.backgroundColor = Palette.c(Self.routePink, 0.95)
        card.addSublayer(pink)
        turnIcon.frame = pink.frame.insetBy(dx: 9, dy: 8)
        turnIcon.contentsGravity = .resizeAspect
        turnIcon.contentsScale = scale
        card.addSublayer(turnIcon)

        for (layer, size, weight, y) in [(turnTitle, CGFloat(12.5), NSFont.Weight.bold, rect.height - 19),
                                         (turnDistance, CGFloat(11), NSFont.Weight.medium, 4)] {
            layer.font = NSFont.systemFont(ofSize: size, weight: weight)
            layer.fontSize = size
            layer.foregroundColor = .white
            layer.contentsScale = scale
            layer.frame = CGRect(x: 10, y: y, width: rect.width - iconW - 14, height: size + 4)
            card.addSublayer(layer)
        }
        turnDistance.foregroundColor = CGColor(gray: 1, alpha: 0.8)
        root.addSublayer(rim(rect, radius: Self.bannerRadius))
        setDirections(title: "Vice City", detail: "Recalculating…", icon: "location.north.fill")
    }

    private func setDirections(title: String, detail: String, icon: String) {
        turnTitle.string = title
        turnDistance.string = detail
        guard icon != iconName else { return }
        iconName = icon
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .bold)
        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            var r = CGRect(origin: .zero, size: img.size)
            turnIcon.contents = img.cgImage(forProposedRect: &r, context: nil, hints: nil)
        }
    }

    // MARK: Updates

    private func toMap(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - screenFrame.minX) * s, y: (p.y - screenFrame.minY) * s)
    }

    func update(windows: [(id: Int, frame: CGRect)]) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)

        do {
            let mine = windows.filter { $0.frame.intersects(screenFrame) }
            var seen = Set<Int>()
            // Back to front, so the front window ends up on top.
            for (i, w) in mine.enumerated().reversed() {
                seen.insert(w.id)
                let rect = CGRect(origin: toMap(w.frame.origin), size: CGSize(width: w.frame.width * s, height: w.frame.height * s))
                    .intersection(blocks.bounds)
                let isFront = i == 0
                let l: CALayer
                if let existing = blockLayers[w.id] {
                    l = existing
                } else {
                    l = CALayer()
                    l.cornerRadius = 2.5
                    CATransaction.setDisableActions(true)
                    l.frame = rect
                    CATransaction.setDisableActions(false)
                    blockLayers[w.id] = l
                }
                l.frame = rect
                l.backgroundColor = Palette.c(isFront ? Self.frontBlock : Self.block, isFront ? 0.85 : 0.6)
                blocks.addSublayer(l)   // re-adding moves it to the top: keeps the stacking order
                if isFront {
                    waypoint.isHidden = false
                    waypoint.position = CGPoint(x: rect.midX, y: rect.midY)
                }
            }
            if mine.isEmpty { waypoint.isHidden = true }
            for (id, l) in blockLayers where !seen.contains(id) {
                l.removeFromSuperlayer()
                blockLayers[id] = nil
            }
        }

        CATransaction.commit()

        updateRoute(from: home, to: waypoint.isHidden ? nil : waypoint.position)
    }

    /// GPS: along the nearest avenue, round one corner onto the street nearest the waypoint, then
    /// in to the waypoint. The banner announces that corner.
    private func updateRoute(from p: CGPoint?, to t: CGPoint?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let p, let t, let vx = verticals.min(by: { abs($0 - p.x) < abs($1 - p.x) }),
              let hy = horizontals.min(by: { abs($0 - t.y) < abs($1 - t.y) }) else {
            route.isHidden = true
            distance.string = ""
            setDirections(title: "Vice City", detail: "No signal", icon: "location.slash.fill")
            return
        }
        let pts = [p, CGPoint(x: vx, y: p.y), CGPoint(x: vx, y: hy), CGPoint(x: t.x, y: hy), t]
        let path = CGMutablePath()
        path.move(to: pts[0])
        for i in 1..<pts.count - 1 {
            path.addArc(tangent1End: pts[i], tangent2End: pts[i + 1], radius: 4)
        }
        path.addLine(to: pts[pts.count - 1])
        route.path = path
        route.isHidden = false
        // The arrow faces along the first leg of the route.
        if let next = pts.dropFirst().first(where: { hypot($0.x - p.x, $0.y - p.y) > 2 }) {
            arrow.transform = CATransform3DMakeRotation(atan2(next.y - p.y, next.x - p.x) - .pi / 2, 0, 0, 1)
        }

        // Distances in "feet": one screen point is roughly one foot of Vice City.
        func len(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(b.x - a.x, b.y - a.y) / s }
        let total = zip(pts, pts.dropFirst()).reduce(0) { $0 + len($1.0, $1.1) }
        if total < 40 {
            distance.string = ""
            setDirections(title: "You have arrived", detail: "Front window", icon: "flag.checkered")
            return
        }
        distance.string = "\(Self.feet(total))"

        // The first real corner along the way.
        var walked: CGFloat = 0
        for i in 1..<pts.count - 1 {
            let a = pts[i - 1], b = pts[i], c = pts[i + 1]
            walked += len(a, b)
            let d1 = CGPoint(x: b.x - a.x, y: b.y - a.y), d2 = CGPoint(x: c.x - b.x, y: c.y - b.y)
            guard hypot(d1.x, d1.y) > 2, hypot(d2.x, d2.y) > 2 else { continue }
            let cross = d1.x * d2.y - d1.y * d2.x
            guard abs(cross) > 1 else { continue }
            setDirections(title: cross > 0 ? "Turn Left" : "Turn Right", detail: Self.feet(walked),
                          icon: cross > 0 ? "arrow.turn.up.left" : "arrow.turn.up.right")
            return
        }
        setDirections(title: "Continue", detail: Self.feet(total), icon: "arrow.up")
    }

    private static func feet(_ points: CGFloat) -> String {
        let ft = Int((points / 10).rounded()) * 10
        return ft >= 1000 ? String(format: "%.1f mi", Double(ft) / 5280) : "\(max(10, ft)) ft"
    }
}
