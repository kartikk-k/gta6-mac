import AppKit
import ApplicationServices

/// macOS's "click wallpaper to reveal desktop" can't see through the theme's desktop-level
/// windows, so we watch for clicks on the bare desktop and trigger the same Show Desktop
/// ourselves, but only if macOS didn't already react to the click.
@MainActor
final class DesktopReveal {
    private var monitor: Any?
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    var dockFrame: () -> CGRect? = { nil }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            let clicks = event.clickCount
            MainActor.assumeIsolated { self?.handleClick(clickCount: clicks) }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private var systemSettingOn: Bool {
        UserDefaults(suiteName: "com.apple.WindowManager")?.object(forKey: "EnableStandardClickToShowDesktop") as? Bool ?? true
    }

    private func handleClick(clickCount: Int) {
        guard clickCount == 1, systemSettingOn, let primary = NSScreen.screens.first else { return }
        let m = NSEvent.mouseLocation
        let point = CGPoint(x: m.x, y: primary.frame.maxY - m.y)   // window-list coordinates (top-left origin)
        guard isBareDesktop(at: point, cocoaPoint: m) else { return }
        let before = appWindowFrames()
        guard !before.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.appWindowFrames() == before else { return }   // macOS already handled it
                CoreDock.toggleShowDesktop()
            }
        }
    }

    private func isBareDesktop(at p: CGPoint, cocoaPoint: CGPoint) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
        let screen = NSScreen.screens.first { $0.frame.contains(cocoaPoint) }?.frame ?? .zero
        for w in list {   // front to back
            guard let pid = w[kCGWindowOwnerPID as String] as? Int32, pid != ownPID,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict), bounds.contains(p) else { continue }
            let layer = w[kCGWindowLayer as String] as? Int ?? 0
            let owner = w[kCGWindowOwnerName as String] as? String ?? ""
            if owner == "Dock" {
                if let dock = dockFrame(), dock.insetBy(dx: -4, dy: -4).contains(cocoaPoint) { return false }
                continue   // the Dock's full-screen transparent window
            }
            if layer < 0 { return !isDesktopIcon(at: p) }   // Finder's desktop or the wallpaper
            if layer > 0, bounds.width >= screen.width - 1, bounds.height >= screen.height - 40 { continue }  // overlays
            return false   // an app window, menu bar, etc.
        }
        return false
    }

    private func isDesktopIcon(at p: CGPoint) -> Bool {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(p.x), Float(p.y), &element) == .success,
              let element else { return false }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard pid != ownPID else { return false }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        let r = role as? String ?? ""
        return r == (kAXImageRole as String) || r == (kAXTextFieldRole as String) || r == (kAXStaticTextRole as String)
    }

    private func appWindowFrames() -> [CGRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { w in
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? Int32) != ownPID,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary else { return nil }
            return CGRect(dictionaryRepresentation: dict)
        }
    }
}

/// The Dock's own Show Desktop toggle (the same thing the F11 / Mission Control gesture does).
enum CoreDock {
    private typealias SendNotification = @convention(c) (CFString, UnsafeMutableRawPointer?) -> Void
    private static let send: SendNotification? = {
        guard let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_NOW),
              let sym = dlsym(handle, "CoreDockSendNotification") else { return nil }
        return unsafeBitCast(sym, to: SendNotification.self)
    }()

    static func toggleShowDesktop() {
        send?("com.apple.showdesktop.awake" as CFString, nil)
    }
}
