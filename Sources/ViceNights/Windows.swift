import AppKit

extension NSWindow.Level {
    /// Same level as the system wallpaper: above it, below desktop icons and every app window.
    static let backdrop = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
    /// Just above the backdrop, still below desktop icons and windows.
    static let skyBehindWindows = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
    /// Above app windows but below the Dock and the menu bar, so aircraft pass behind both.
    static let skyOverWindows = NSWindow.Level.floating
    /// Corner palms behind windows: on the desktop, under app windows and the Dock's glass.
    static let dockDecor = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 2)
    /// The Dock's neon outline sits just above the Dock so its glass doesn't swallow the line.
    /// It only covers the Dock's own strip, where app windows never go.
    static let aboveDock = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
}

/// Borderless, transparent, click-through window present on every Space.
final class OverlayWindow: NSWindow {
    init(frame: CGRect, level: NSWindow.Level) {
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.level = level
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A view that hosts a plain CALayer tree (y-up coordinates).
class LayerHostView: NSView {
    let root = CALayer()

    init(size: CGSize) {
        super.init(frame: CGRect(origin: .zero, size: size))
        root.frame = bounds
        layer = root
        wantsLayer = true
        layerUsesCoreImageFilters = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}

enum Anim {
    static func fade(_ layer: CALayer, to value: Float, duration: Double, completion: (() -> Void)? = nil) {
        let from = layer.presentation()?.opacity ?? layer.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock(completion)
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = from
        a.toValue = value
        a.duration = duration
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.opacity = value
        layer.add(a, forKey: "fade")
        CATransaction.commit()
    }

    /// Start a repeating animation at a random phase so identical elements don't pulse in sync.
    static func randomPhase(_ a: CAAnimation) -> CAAnimation {
        a.timeOffset = Double.random(in: 0...max(0.01, a.duration))
        return a
    }

    /// Cap slow ambient animations to a low frame rate so the WindowServer isn't
    /// recompositing full-screen layers at 120 Hz for motion nobody can see.
    @discardableResult
    static func throttle(_ a: CAAnimation, fps: Float) -> CAAnimation {
        a.preferredFrameRateRange = CAFrameRateRange(minimum: max(1, fps / 2), maximum: fps, preferred: fps)
        return a
    }

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}
