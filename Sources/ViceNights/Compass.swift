import AppKit

/// Where the Mac roughly is, without asking for Location permission: the coordinates the
/// system time-zone table lists for the current zone (e.g. Asia/Kolkata → 22.5°N 88.4°E).
enum HomeLocation {
    static let coordinate: (lat: Double, lon: Double) = {
        let id = TimeZone.current.identifier
        for path in ["/usr/share/zoneinfo/zone.tab", "/var/db/timezone/zoneinfo/zone.tab"] {
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") where !line.hasPrefix("#") {
                let cols = line.split(separator: "\t")
                guard cols.count >= 3, cols[2] == id, let c = parse(cols[1]) else { continue }
                return c
            }
        }
        // Unknown zone: Vice City's latitude, longitude from the UTC offset.
        return (25.77, Double(TimeZone.current.secondsFromGMT()) / 240)
    }()

    /// "+2232+08822" or "+404251-0740023" (±DDMM[SS]±DDDMM[SS]).
    private static func parse(_ s: Substring) -> (lat: Double, lon: Double)? {
        let chars = Array(s)
        guard let split = chars.indices.dropFirst().first(where: { chars[$0] == "+" || chars[$0] == "-" }) else { return nil }
        func value(_ part: ArraySlice<Character>, degDigits: Int) -> Double? {
            guard let sign = part.first else { return nil }
            let digits = Array(part.dropFirst())
            guard digits.count >= degDigits + 2 else { return nil }
            func num(_ a: Int, _ b: Int) -> Double { Double(String(digits[a..<min(b, digits.count)])) ?? 0 }
            var v = num(0, degDigits) + num(degDigits, degDigits + 2) / 60
            if digits.count >= degDigits + 4 { v += num(degDigits + 2, degDigits + 4) / 3600 }
            return sign == "-" ? -v : v
        }
        guard let lat = value(chars[..<split], degDigits: 2), let lon = value(chars[split...], degDigits: 3) else { return nil }
        return (lat, lon)
    }
}

enum Bearings {
    static let viceCity = (lat: 25.7743, lon: -80.1937)   // Miami, the real Vice City

    /// The sun's compass bearing (0 = north, clockwise) and height above the horizon, in degrees
    /// (NOAA's low-precision formulas, good to well under a degree).
    static func sun(at date: Date = Date(), lat: Double, lon: Double) -> (azimuth: Double, elevation: Double) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let day = Double(cal.ordinality(of: .day, in: .year, for: date) ?? 1)
        let c = cal.dateComponents([.hour, .minute, .second], from: date)
        let hour = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
        let g = 2 * Double.pi / 365 * (day - 1 + (hour - 12) / 24)
        let eqTime = 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g) - 0.014615 * cos(2 * g) - 0.040849 * sin(2 * g))
        let decl = 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g) - 0.006758 * cos(2 * g)
            + 0.000907 * sin(2 * g) - 0.002697 * cos(3 * g) + 0.00148 * sin(3 * g)
        let solarMinutes = hour * 60 + eqTime + 4 * lon
        let ha = (solarMinutes / 4 - 180) * .pi / 180
        let phi = lat * .pi / 180
        let cosZenith = sin(phi) * sin(decl) + cos(phi) * cos(decl) * cos(ha)
        let elevation = 90 - acos(max(-1, min(1, cosZenith))) * 180 / .pi
        let az = atan2(sin(ha), cos(ha) * sin(phi) - tan(decl) * cos(phi)) * 180 / .pi + 180
        return (normalize(az), elevation)
    }

    /// Initial great-circle bearing from one place to another.
    static func bearing(from a: (lat: Double, lon: Double), to b: (lat: Double, lon: Double)) -> Double {
        let p1 = a.lat * .pi / 180, p2 = b.lat * .pi / 180, dl = (b.lon - a.lon) * .pi / 180
        let y = sin(dl) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        return normalize(atan2(y, x) * 180 / .pi)
    }

    static func normalize(_ d: Double) -> Double { (d.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) }

    static func compassPoint(_ d: Double) -> String {
        let names = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        return names[Int((normalize(d) + 11.25) / 22.5) % 16]
    }

    /// For the menu: "Sun 247° WSW, 32° up · Vice City 319° NW".
    static func summary() -> String {
        let home = HomeLocation.coordinate
        let s = sun(lat: home.lat, lon: home.lon)
        let vc = bearing(from: home, to: viceCity)
        let sunText = s.elevation > 0
            ? "Sun \(Int(s.azimuth.rounded()))° \(compassPoint(s.azimuth)), \(Int(s.elevation.rounded()))° up"
            : "Sun \(Int(s.azimuth.rounded()))° \(compassPoint(s.azimuth)), below the horizon"
        return "\(sunText) · Vice City \(Int(vc.rounded()))° \(compassPoint(vc))"
    }
}

/// The in-game compass: a thin line under the menu bar with N · E · S · W, tick marks, a pointer
/// in the middle, a sun marker at the sun's real bearing and a pink waypoint pointing to Vice City.
/// The heading follows the mouse like mouse-look in the game (move right, turn right), easing to a
/// stop, and wanders on its own when the mouse is still. Reading the pointer position needs no
/// permissions.
///
/// Cost: the whole tape is drawn once and cached as a bitmap; the only thing that changes is its
/// x-position and, once a minute, the sun marker.
final class CompassView: LayerHostView {
    static let size = CGSize(width: 420, height: 34)
    private static let span: CGFloat = 170          // degrees visible across the strip
    private static let lineY: CGFloat = 21
    private static let mouseGain: CGFloat = 0.12    // degrees of turn per point of mouse travel

    private let tape = CALayer()
    private let sunMarker = CALayer()
    private var sunTimer: Timer?
    private var tickTimer: Timer?
    private var heading = CGFloat.random(in: 0..<360)
    private var target: CGFloat = 0
    private var wander: CGFloat = 0                  // idle turning speed, degrees per second
    private var wanderGoal: CGFloat = 0
    private var wanderUntil = Date()
    private var lastMouseX = NSEvent.mouseLocation.x
    private var lastTick = Date()
    private let k: CGFloat                           // points per degree
    private let scale: CGFloat

    init(scale: CGFloat) {
        self.scale = scale
        k = Self.size.width / Self.span
        super.init(size: Self.size)
        let W = Self.size.width, H = Self.size.height

        // A soft dark scrim so the letters read over bright title bars.
        let scrim = CAGradientLayer()
        scrim.type = .radial
        scrim.frame = bounds.insetBy(dx: W * 0.08, dy: -4)
        scrim.colors = [Palette.c(0x0b0b16, 0.38), Palette.c(0x0b0b16, 0)]
        scrim.startPoint = CGPoint(x: 0.5, y: 0.5)
        scrim.endPoint = CGPoint(x: 1, y: 1)
        root.addSublayer(scrim)

        // The moving tape, faded out at both ends.
        let window = CALayer()
        window.frame = bounds
        let fade = CAGradientLayer()
        fade.frame = bounds
        fade.colors = [CGColor(gray: 1, alpha: 0), CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)]
        fade.locations = [0, 0.22, 0.78, 1]
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        window.mask = fade
        root.addSublayer(window)

        // Bearings -180…540: two full turns' worth, so panning 0→360 loops seamlessly.
        tape.anchorPoint = .zero
        tape.bounds = CGRect(x: 0, y: 0, width: 720 * k, height: H)
        buildTape()
        tape.shadowColor = .black
        tape.shadowOpacity = 0.6
        tape.shadowRadius = 2
        tape.shadowOffset = .zero
        tape.shouldRasterize = true
        tape.rasterizationScale = scale
        window.addSublayer(tape)

        // Fixed pointer in the middle: the way "you" are facing.
        let pointer = CAShapeLayer()
        let p = CGMutablePath()
        p.move(to: CGPoint(x: W / 2 - 4, y: Self.lineY + 9))
        p.addLine(to: CGPoint(x: W / 2 + 4, y: Self.lineY + 9))
        p.addLine(to: CGPoint(x: W / 2, y: Self.lineY + 3))
        p.closeSubpath()
        pointer.path = p
        pointer.fillColor = CGColor(gray: 1, alpha: 0.95)
        pointer.shadowColor = .black
        pointer.shadowOpacity = 0.6
        pointer.shadowRadius = 1.5
        pointer.shadowOffset = .zero
        pointer.contentsScale = scale
        root.addSublayer(pointer)

        updateSun()
        sunTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateSun() }
        }

        if Anim.reduceMotion {
            // Hold still, facing the sun.
            let az = CGFloat(Bearings.sun(lat: HomeLocation.coordinate.lat, lon: HomeLocation.coordinate.lon).azimuth)
            tape.position = CGPoint(x: x(heading: az), y: 0)
        } else {
            target = heading
            tape.position = CGPoint(x: x(heading: heading), y: 0)
            tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 40, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            tickTimer?.tolerance = 0.005
        }
    }

    private func tick() {
        let now = Date()
        let dt = CGFloat(min(0.1, now.timeIntervalSince(lastTick)))
        lastTick = now

        // Mouse-look: horizontal pointer travel turns the heading.
        let mx = NSEvent.mouseLocation.x
        var dx = mx - lastMouseX
        lastMouseX = mx
        if abs(dx) > 600 { dx = 0 }   // jumped between screens
        target += dx * Self.mouseGain

        // Idle wander: a gentle turn that changes speed and direction every few seconds.
        if now >= wanderUntil {
            wanderGoal = CGFloat.random(in: 2...6) * (Bool.random() ? 1 : -1)
            wanderUntil = now.addingTimeInterval(.random(in: 3...8))
        }
        wander += (wanderGoal - wander) * min(1, dt * 0.8)
        target += wander * dt

        // Ease toward the target so turns glide to a stop instead of snapping.
        let before = heading
        heading += (target - heading) * min(1, dt * 7)
        if heading >= 360 { heading -= 360; target -= 360 }
        if heading < 0 { heading += 360; target += 360 }
        guard abs(heading - before) * k * scale > 0.05 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tape.position = CGPoint(x: x(heading: heading), y: 0)
        CATransaction.commit()
    }

    deinit {
        sunTimer?.invalidate()
        tickTimer?.invalidate()
    }

    /// Tape x-position that puts `heading` under the pointer.
    private func x(heading: CGFloat) -> CGFloat { Self.size.width / 2 - (heading + 180) * k }
    /// Where a bearing sits on the tape.
    private func tapeX(_ bearing: CGFloat) -> CGFloat { (bearing + 180) * k }

    private func buildTape() {
        let y = Self.lineY
        // The line.
        let line = CALayer()
        line.frame = CGRect(x: 0, y: y - 0.5, width: tape.bounds.width, height: 1)
        line.backgroundColor = CGColor(gray: 1, alpha: 0.55)
        tape.addSublayer(line)

        // Ticks every 15°, longer every 45°.
        let ticks = CAShapeLayer()
        let tp = CGMutablePath()
        for b in stride(from: -180, through: 540, by: 15) {
            let major = b % 45 == 0
            let len: CGFloat = major ? 3.5 : 2
            tp.move(to: CGPoint(x: tapeX(CGFloat(b)), y: y - len))
            tp.addLine(to: CGPoint(x: tapeX(CGFloat(b)), y: y + len))
        }
        ticks.path = tp
        ticks.strokeColor = CGColor(gray: 1, alpha: 0.6)
        ticks.lineWidth = 1
        ticks.contentsScale = scale
        tape.addSublayer(ticks)

        // Letters just under the line.
        let font = NSFont.systemFont(ofSize: 10.5, weight: .heavy, width: .condensed)
        for b in stride(from: -180, through: 540, by: 90) {
            let name = ["N", "E", "S", "W"][Int(Bearings.normalize(Double(b)) / 90)]
            let t = CATextLayer()
            t.string = NSAttributedString(string: name, attributes: [
                .font: font,
                .foregroundColor: NSColor(white: 1, alpha: name == "N" ? 1 : 0.85),
            ])
            t.alignmentMode = .center
            t.contentsScale = scale
            t.frame = CGRect(x: tapeX(CGFloat(b)) - 10, y: y - 19, width: 20, height: 14)
            tape.addSublayer(t)
        }

        // Pink waypoint: the bearing from here to Vice City.
        let vc = CGFloat(Bearings.bearing(from: HomeLocation.coordinate, to: Bearings.viceCity))
        for b in [vc - 360, vc, vc + 360] where b >= -180 && b <= 540 {
            let d = CAShapeLayer()
            let r: CGFloat = 4
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 0, y: r)); p.addLine(to: CGPoint(x: r, y: 0))
            p.addLine(to: CGPoint(x: 0, y: -r)); p.addLine(to: CGPoint(x: -r, y: 0)); p.closeSubpath()
            d.path = p
            d.fillColor = Palette.c(Palette.neonPink)
            d.strokeColor = CGColor(gray: 1, alpha: 0.9)
            d.lineWidth = 0.8
            d.position = CGPoint(x: tapeX(b), y: y)
            d.contentsScale = scale
            tape.addSublayer(d)
        }

        sunMarker.frame = tape.bounds
        tape.addSublayer(sunMarker)
    }

    /// The sun at its real bearing: a warm disc by day, a faint ring once it has set.
    private func updateSun() {
        let home = HomeLocation.coordinate
        let s = Bearings.sun(lat: home.lat, lon: home.lon)
        let az = CGFloat(s.azimuth)
        let up = s.elevation > -0.8
        sunMarker.sublayers?.forEach { $0.removeFromSuperlayer() }
        for b in [az - 360, az, az + 360] where b >= -180 && b <= 540 {
            let m = CAShapeLayer()
            let r: CGFloat = up ? 4.5 : 3.6
            m.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r), transform: nil)
            if up {
                m.fillColor = Palette.c(Palette.warmWindow)
                m.strokeColor = Palette.c(0xffffff, 0.9)
                m.lineWidth = 0.8
            } else {
                m.fillColor = nil
                m.strokeColor = Palette.c(Palette.warmWindow, 0.75)
                m.lineWidth = 1.2
            }
            m.position = CGPoint(x: tapeX(b), y: Self.lineY)
            m.contentsScale = scale
            sunMarker.addSublayer(m)
        }
    }
}
