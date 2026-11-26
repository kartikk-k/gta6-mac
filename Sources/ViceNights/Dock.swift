import AppKit
import ApplicationServices

/// Finds the Dock's on-screen frame (global Cocoa coordinates).
@MainActor
enum DockLocator {
    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func frame() -> CGRect? {
        let dockDefaults = UserDefaults(suiteName: "com.apple.dock")
        if dockDefaults?.bool(forKey: "autohide") == true { return nil }
        let orientation = dockDefaults?.string(forKey: "orientation") ?? "bottom"
        guard orientation == "bottom" else { return nil }
        let rect = accessibilityFrame() ?? estimatedFrame()
        guard let rect, rect.width > 40 else { return nil }
        return rect
    }

    /// Exact: the Dock's AXList element. Needs Accessibility permission.
    private static func accessibilityFrame() -> CGRect? {
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
              let primary = NSScreen.screens.first else { return nil }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &children) == .success,
              let elements = children as? [AXUIElement] else { return nil }
        for element in elements {
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            guard (role as? String) == (kAXListRole as String) else { continue }
            var posRef: CFTypeRef?, sizeRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
                  AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
                  let posRef, let sizeRef else { continue }
            var point = CGPoint.zero, size = CGSize.zero
            AXValueGetValue(posRef as! AXValue, .cgPoint, &point)
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
            // AX uses a top-left origin on the primary display.
            return CGRect(x: point.x, y: primary.frame.maxY - point.y - size.height, width: size.width, height: size.height)
        }
        return nil
    }

    /// Fallback without permission: height from the reserved screen area, width from the Dock's item count.
    private static func estimatedFrame() -> CGRect? {
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.minY - $0.frame.minY > 20 }) else { return nil }
        let band = screen.visibleFrame.minY - screen.frame.minY
        let d = UserDefaults(suiteName: "com.apple.dock")
        let tile = CGFloat(d?.double(forKey: "tilesize") ?? 48)
        let persistent = d?.array(forKey: "persistent-apps") ?? []
        let persistentIDs = Set(persistent.compactMap {
            (($0 as? [String: Any])?["tile-data"] as? [String: Any])?["bundle-identifier"] as? String
        })
        let extra = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != "com.apple.finder"
                && !persistentIDs.contains($0.bundleIdentifier ?? "")
        }.count
        let others = (d?.array(forKey: "persistent-others") ?? []).count
        let showRecents = d?.object(forKey: "show-recents") as? Bool ?? true
        let recents = showRecents ? min(3, (d?.array(forKey: "recent-apps") ?? []).count) : 0
        let items = CGFloat(1 + persistent.count + max(extra, recents) + others + 1)
        let width = min(screen.frame.width - 16, items * (tile + 4) + 2 * 18 + 16)
        let height = band - 6
        return CGRect(x: screen.frame.midX - width / 2, y: screen.frame.minY + 10, width: width, height: height)
    }
}

/// Neon outline and palm trees drawn just beneath the Dock.
@MainActor
final class DockDecor {
    private var window: OverlayWindow?        // palms, behind windows
    private var neonWindow: OverlayWindow?    // outline, just above the Dock
    private var timer: Timer?
    private var builtKey = ""
    private(set) var dockFrame: CGRect?

    private static let padX: CGFloat = 150
    private static let padBottom: CGFloat = 16
    private static let padTop: CGFloat = 130

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
        window = nil
        neonWindow?.orderOut(nil)
        neonWindow = nil
        builtKey = ""
        dockFrame = nil
    }

    func refresh(force: Bool = false) {
        let s = Settings.shared
        let rect = DockLocator.frame()
        dockFrame = rect
        let wantNeon = s.isOn(.dockNeon), wantPalms = s.isOn(.dockPalms)
        guard let rect, wantNeon || wantPalms else {
            window?.orderOut(nil)
            window = nil
            neonWindow?.orderOut(nil)
            neonWindow = nil
            builtKey = ""
            return
        }
        let r = rect.integral
        let key = "\(r)|\(wantNeon)|\(wantPalms)"
        guard force || key != builtKey else { return }
        builtKey = key

        let frame = CGRect(x: r.minX - Self.padX, y: r.minY - Self.padBottom,
                           width: r.width + Self.padX * 2, height: r.height + Self.padBottom + Self.padTop)
        let local = CGRect(x: Self.padX, y: Self.padBottom, width: r.width, height: r.height)
        let scale = NSScreen.screens.first(where: { $0.frame.intersects(r) })?.backingScaleFactor ?? 2
        if wantPalms {
            if window == nil { window = OverlayWindow(frame: frame, level: .dockDecor) }
            window?.setFrame(frame, display: false)
            window?.contentView = DockDecorView(size: frame.size, dock: local, neon: false, palms: true, scale: scale)
            window?.orderFrontRegardless()
        } else {
            window?.orderOut(nil)
            window = nil
        }
        // The neon window hugs the Dock tightly (just room for the glow), so it never covers app windows.
        let glowPad: CGFloat = 18
        let neonFrame = r.insetBy(dx: -glowPad, dy: -glowPad)
        let neonLocal = CGRect(x: glowPad, y: glowPad, width: r.width, height: r.height)
        if wantNeon {
            if neonWindow == nil { neonWindow = OverlayWindow(frame: neonFrame, level: .aboveDock) }
            neonWindow?.setFrame(neonFrame, display: false)
            neonWindow?.contentView = DockDecorView(size: neonFrame.size, dock: neonLocal, neon: true, palms: false, scale: scale)
            neonWindow?.orderFrontRegardless()
        } else {
            neonWindow?.orderOut(nil)
            neonWindow = nil
        }
    }
}

final class DockDecorView: LayerHostView {
    private var flickerTimer: Timer?

    init(size: CGSize, dock: CGRect, neon: Bool, palms: Bool, scale: CGFloat) {
        super.init(size: size)
        if palms { addPalms(dock: dock, scale: scale) }
        if neon { addNeon(dock: dock, scale: scale) }
    }

    deinit { flickerTimer?.invalidate() }

    private func addPalms(dock: CGRect, scale: CGFloat) {
        let h = dock.height * 1.95
        let specs: [(x: CGFloat, h: CGFloat, lean: CGFloat, seed: UInt64)] = [
            (dock.minX + dock.height * 0.35, h, -0.5, 11),
            (dock.minX + dock.height * 0.95, h * 0.72, -0.85, 17),
            (dock.maxX - dock.height * 0.35, h, 0.5, 23),
            (dock.maxX - dock.height * 0.95, h * 0.72, 0.85, 29),
        ]
        for spec in specs {
            let l = CAShapeLayer()
            l.path = Shapes.palm(height: spec.h, lean: spec.lean, fronds: 9, seed: spec.seed)
            l.fillColor = Palette.c(Palette.palmSlate)
            l.contentsScale = scale
            l.bounds = .zero
            l.position = CGPoint(x: spec.x, y: dock.minY + 4)
            if !Anim.reduceMotion { SkylineScene.sway(l, amount: 0.018) }
            root.addSublayer(l)
        }
    }

    private func addNeon(dock: CGRect, scale: CGFloat) {
        // Measured against the visible glass: 1.5pt in from the sides, reaching 4pt lower at the
        // bottom than the AX frame suggests, with a corner radius 2pt tighter than before.
        let outline = CGRect(x: dock.minX + 1.5, y: dock.minY - 5.5, width: dock.width - 3, height: dock.height + 0.5)
        let radius = max(4, min((dock.height - 3.5) * 0.36, 30) - 2)
        let path = CGPath(roundedRect: outline, cornerWidth: radius, cornerHeight: radius, transform: nil)

        let neonLayer = CALayer()
        neonLayer.frame = bounds
        root.addSublayer(neonLayer)

        // Soft bloom: a few wide, faint strokes (rasterised once) under the tube.
        let bloomMask = CALayer()
        bloomMask.frame = bounds
        for (width, alpha) in [(16.0, 0.05), (10.0, 0.1), (6.0, 0.18)] as [(CGFloat, CGFloat)] {
            bloomMask.addSublayer(stroke(path, width: width, alpha: alpha, scale: scale))
        }
        bloomMask.shouldRasterize = true
        bloomMask.rasterizationScale = scale
        let bloom = CALayer()
        bloom.frame = bounds
        bloom.mask = bloomMask
        bloom.addSublayer(flowingGradient())
        neonLayer.addSublayer(bloom)

        // The tube itself: one crisp, fully opaque vector stroke drawn at the display's
        // resolution, so the line stays sharp while the colours flow along it.
        let tube = CALayer()
        tube.frame = bounds
        tube.mask = stroke(path, width: 2, alpha: 1, scale: scale)
        tube.addSublayer(flowingGradient())
        neonLayer.addSublayer(tube)

        if !Anim.reduceMotion { scheduleFlicker(neonLayer) }
    }

    private func stroke(_ path: CGPath, width: CGFloat, alpha: CGFloat, scale: CGFloat) -> CAShapeLayer {
        let l = CAShapeLayer()
        l.frame = bounds
        l.path = path
        l.fillColor = nil
        l.strokeColor = CGColor(gray: 1, alpha: alpha)
        l.lineWidth = width
        l.contentsScale = scale
        return l
    }

    /// A repeating pink → violet → cyan gradient, twice as wide as the view, sliding sideways by
    /// exactly one repeat so the colours flow along the outline in a seamless loop.
    private func flowingGradient() -> CAGradientLayer {
        let pink = Palette.c(Palette.neonPink), violet = Palette.c(Palette.neonViolet), cyan = Palette.c(Palette.neonCyan)
        let slider = CAGradientLayer()
        slider.frame = CGRect(x: 0, y: 0, width: bounds.width * 2, height: bounds.height)
        slider.colors = [pink, violet, cyan, violet, pink, violet, cyan, violet, pink]
        slider.startPoint = CGPoint(x: 0, y: 0.5)
        slider.endPoint = CGPoint(x: 1, y: 0.5)
        if !Anim.reduceMotion {
            let flow = CABasicAnimation(keyPath: "position.x")
            flow.fromValue = bounds.width
            flow.toValue = 0
            flow.duration = 7
            flow.repeatCount = .infinity
            flow.timingFunction = CAMediaTimingFunction(name: .linear)
            slider.add(Anim.throttle(flow, fps: 30), forKey: "flow")
        }
        return slider
    }

    /// Every so often the tube stutters like a real neon sign.
    private func scheduleFlicker(_ layer: CALayer) {
        flickerTimer = Timer.scheduledTimer(withTimeInterval: .random(in: 7...18), repeats: false) { [weak self, weak layer] _ in
            MainActor.assumeIsolated {
                guard let layer else { return }
                let a = CAKeyframeAnimation(keyPath: "opacity")
                a.values = [1, 0.25, 1, 0.55, 1, 0.8, 1]
                a.keyTimes = [0, 0.1, 0.2, 0.35, 0.5, 0.7, 1]
                a.duration = 0.45
                layer.add(a, forKey: "flicker")
                self?.scheduleFlicker(layer)
            }
        }
    }
}
