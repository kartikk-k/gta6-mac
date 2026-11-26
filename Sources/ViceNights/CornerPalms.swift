import AppKit

/// Big palms in the bottom corners of every screen. The hazy back pair stands on the desktop,
/// behind app windows; the dark foreground palm leans in from the edge and, when
/// "Palms Over Windows" is on, overlaps the corners of windows a little.
@MainActor
final class CornerPalms {
    private var windows: [OverlayWindow] = []

    func rebuild() {
        stop()
        let s = Settings.shared
        guard s.isOn(.themeOn), s.isOn(.dockPalms) else { return }
        let frontLevel: NSWindow.Level = s.isOn(.palmsOverWindows) ? .skyOverWindows : .dockDecor
        for screen in NSScreen.screens {
            let palms = CornerLayout.palms(screen: screen.frame.size)
            for front in [false, true] {
                for leftSide in [true, false] {
                    let group = palms.filter { $0.front == front && ($0.base.x < screen.frame.width / 2) == leftSide }
                    if let w = makeWindow(group, screen: screen, level: front ? frontLevel : .dockDecor) {
                        windows.append(w)
                    }
                }
            }
        }
    }

    func stop() {
        windows.forEach { $0.orderOut(nil) }
        windows = []
    }

    /// One window per corner and depth, sized tightly around its palms so it covers as little as possible.
    private func makeWindow(_ group: [CornerLayout.Palm], screen: NSScreen, level: NSWindow.Level) -> OverlayWindow? {
        let isFront = group.first?.front == true
        let style: PalmArt.Style = isFront ? .front : .back
        // The back palms are soft and hazy anyway, so they don't need full Retina pixels;
        // 1.5x keeps them crisp while using about half the memory.
        let scale = isFront ? screen.backingScaleFactor : min(1.5, screen.backingScaleFactor)
        var items: [(PalmArt.Rendered, CornerLayout.Palm, CGRect)] = []
        var union = CGRect.null
        for p in group {
            guard let r = PalmArt.render(height: p.height, lean: p.lean, fronds: p.fronds, seed: p.seed,
                                         style: style, scale: scale) else { continue }
            let rect = CGRect(x: p.base.x - r.anchor.x * r.size.width, y: p.base.y - r.anchor.y * r.size.height,
                              width: r.size.width, height: r.size.height)
            items.append((r, p, rect))
            union = union.union(rect)
        }
        // Leave room for the sway, then keep it on the screen.
        let local = union.insetBy(dx: -24, dy: -24).intersection(CGRect(origin: .zero, size: screen.frame.size)).integral
        guard !items.isEmpty, !local.isEmpty else { return nil }

        let frame = local.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        let view = LayerHostView(size: local.size)
        for (r, p, _) in items {
            let l = CALayer()
            l.contents = r.image
            l.contentsScale = scale
            l.bounds = CGRect(origin: .zero, size: r.size)
            l.anchorPoint = r.anchor
            l.position = CGPoint(x: p.base.x - local.minX, y: p.base.y - local.minY)
            if !Anim.reduceMotion { SkylineScene.sway(l, amount: p.front ? 0.012 : 0.016) }
            view.root.addSublayer(l)
        }
        let w = OverlayWindow(frame: frame, level: level)
        w.contentView = view
        w.orderFrontRegardless()
        return w
    }
}
