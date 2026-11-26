import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var backdropWindows: [OverlayWindow] = []
    private var skyWindows: [OverlayWindow] = []
    private var edgeWindows: [OverlayWindow] = []
    private var partyWindows: [OverlayWindow] = []
    private var hazeWindows: [OverlayWindow] = []
    private var compassWindows: [OverlayWindow] = []
    private let reveal = DesktopReveal()
    private let sparks = SparkDirector()
    private let wallpaper = WallpaperDirector()
    private let traffic = TrafficDirector()
    private let dock = DockDecor()
    private let palms = CornerPalms()
    private let minimap = MinimapDirector()
    private var quoteIndex = Int.random(in: 0..<Catalog.quotes.count)

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Icons.statusPalm()
        statusItem.button?.toolTip = "Vice Nights"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        traffic.dockFrame = { [weak self] in self?.dock.dockFrame }
        reveal.dockFrame = { [weak self] in self?.dock.dockFrame }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)

        let settings = Settings.shared
        if !settings.askedForAccessibility && !DockLocator.hasAccessibility {
            settings.askedForAccessibility = true
            DockLocator.requestAccessibility()
        }
        applyTheme()
    }

    func applicationWillTerminate(_ notification: Notification) {
        tearDown()   // Our windows go away; the real wallpaper was never changed.
    }

    // MARK: Theme lifecycle

    private func applyTheme() {
        tearDown()
        guard Settings.shared.isOn(.themeOn) else { return }
        let over = Settings.shared.isOn(.flyOverWindows)
        var backdrops: [BackdropView] = []
        var skies: [SkyView] = []
        for screen in NSScreen.screens {
            let bw = OverlayWindow(frame: screen.frame, level: .backdrop)
            let bv = BackdropView(size: screen.frame.size, scale: screen.backingScaleFactor)
            bw.contentView = bv
            bw.orderFrontRegardless()
            backdropWindows.append(bw)
            backdrops.append(bv)

            let sw = OverlayWindow(frame: screen.frame, level: over ? .skyOverWindows : .skyBehindWindows)
            let sv = SkyView(screen: screen)
            sw.contentView = sv
            sw.orderFrontRegardless()
            skyWindows.append(sw)
            skies.append(sv)
        }
        wallpaper.views = backdrops
        wallpaper.start()
        dock.start()
        palms.rebuild()
        minimap.start()
        traffic.skies = skies
        traffic.start()
        sparks.views = skies
        sparks.start()
        reveal.start()
        buildEdgeGlow()
        buildPartyOverlay()
        buildHaze()
        buildCompass()
    }

    /// The dreamy haze: over apps by default, or just above the wallpaper.
    private func buildHaze() {
        hazeWindows.forEach { $0.orderOut(nil) }
        hazeWindows = []
        let s = Settings.shared
        guard s.isOn(.themeOn), s.isOn(.dreamyHaze) else { return }
        let over = s.isOn(.hazeOverApps)
        for screen in NSScreen.screens {
            let w = OverlayWindow(frame: screen.frame, level: over ? .skyOverWindows : .skyBehindWindows)
            w.contentView = DreamyHazeView(size: screen.frame.size, overApps: over)
            w.orderFrontRegardless()
            hazeWindows.append(w)
        }
    }

    /// Party lights over every app (only when "Party Lights Over Apps" is on).
    private func buildPartyOverlay() {
        partyWindows.forEach { $0.orderOut(nil) }
        partyWindows = []
        let s = Settings.shared
        guard s.isOn(.themeOn), s.isOn(.clubBeams), s.isOn(.partyOverApps), !Anim.reduceMotion else { return }
        for screen in NSScreen.screens {
            let w = OverlayWindow(frame: screen.frame, level: .skyOverWindows)
            w.contentView = PartyLightsView(size: screen.frame.size)
            w.orderFrontRegardless()
            partyWindows.append(w)
        }
    }

    /// The game-style compass strip, centred just under the menu bar.
    private func buildCompass() {
        compassWindows.forEach { $0.orderOut(nil) }
        compassWindows = []
        let s = Settings.shared
        guard s.isOn(.themeOn), s.isOn(.compass) else { return }
        let level: NSWindow.Level = s.isOn(.compassOverWindows) ? .skyOverWindows : .skyBehindWindows
        for screen in NSScreen.screens {
            let size = CompassView.size
            let menuBar = max(24, screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top)
            let frame = CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - menuBar - size.height - 2,
                               width: size.width, height: size.height)
            let w = OverlayWindow(frame: frame, level: level)
            w.contentView = CompassView(scale: screen.backingScaleFactor)
            w.orderFrontRegardless()
            compassWindows.append(w)
        }
    }

    private func buildEdgeGlow() {
        edgeWindows.forEach { $0.orderOut(nil) }
        edgeWindows = []
        guard Settings.shared.isOn(.themeOn), Settings.shared.isOn(.edgeGlow) else { return }
        for screen in NSScreen.screens {
            let w = OverlayWindow(frame: screen.frame, level: .edgeGlow)
            w.contentView = EdgeGlowView(screen: screen)
            w.orderFrontRegardless()
            edgeWindows.append(w)
        }
    }

    private func tearDown() {
        wallpaper.stop()
        traffic.stop()
        sparks.stop()
        dock.stop()
        palms.stop()
        minimap.stop()
        reveal.stop()
        (backdropWindows + skyWindows + edgeWindows + partyWindows + hazeWindows + compassWindows).forEach { $0.orderOut(nil) }
        backdropWindows = []
        skyWindows = []
        edgeWindows = []
        partyWindows = []
        hazeWindows = []
        compassWindows = []
    }

    @objc private func screensChanged() {
        guard Settings.shared.isOn(.themeOn) else { return }
        applyTheme()
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = Settings.shared
        let on = s.isOn(.themeOn)

        let header = NSMenuItem(title: "Vice Nights", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        quoteIndex = (quoteIndex + 1) % Catalog.quotes.count
        let (quote, who) = Catalog.quotes[quoteIndex]
        let quoteItem = NSMenuItem(title: "“\(quote)” — \(who)", action: nil, keyEquivalent: "")
        quoteItem.isEnabled = false
        menu.addItem(quoteItem)
        menu.addItem(.separator())

        menu.addItem(item(on ? "Theme On" : "Theme Off", #selector(toggleTheme), key: "t", checked: on))
        menu.addItem(.separator())

        // Wallpaper
        let wpMenu = NSMenu()
        for set in WallpaperSet.allCases {
            let i = item(set.title, #selector(chooseSet(_:)), checked: s.wallpaperSet == set)
            i.representedObject = set.rawValue
            wpMenu.addItem(i)
            if set == .downtown { wpMenu.addItem(.separator()) }
        }
        wpMenu.addItem(.separator())
        wpMenu.addItem(item("Next Wallpaper", #selector(nextWallpaper), key: "n", enabled: on))
        let every = NSMenu()
        for (title, minutes) in [("5 minutes", 5), ("10 minutes", 10), ("30 minutes", 30), ("1 hour", 60), ("Never", 0)] {
            let i = item(title, #selector(chooseRotation(_:)), checked: s.rotateMinutes == minutes)
            i.tag = minutes
            every.addItem(i)
        }
        let everyItem = NSMenuItem(title: "Change Every", action: nil, keyEquivalent: "")
        everyItem.submenu = every
        wpMenu.addItem(everyItem)
        wpMenu.addItem(.separator())
        wpMenu.addItem(flagItem("Slow Drift", .drift))
        wpMenu.addItem(flagItem("Vice Colour Grade", .viceGrade))
        wpMenu.addItem(flagItem("Lens Colour Fringing", .lensFringe))

        let wpItem = NSMenuItem(title: "Wallpaper", action: nil, keyEquivalent: "")
        wpItem.submenu = wpMenu
        menu.addItem(wpItem)
        if on {
            let now = NSMenuItem(title: "Now showing: \(wallpaper.status.isEmpty ? "…" : wallpaper.status)", action: nil, keyEquivalent: "")
            now.isEnabled = false
            menu.addItem(now)
        }
        menu.addItem(.separator())

        // Sky
        let skyMenu = NSMenu()
        skyMenu.addItem(flagItem("Helicopters", .helicopters))
        skyMenu.addItem(flagItem("Police Searchlights", .searchlights))
        skyMenu.addItem(flagItem("Distant Jets", .jets))
        skyMenu.addItem(flagItem("Birds", .birds))
        skyMenu.addItem(.separator())
        for t in Traffic.allCases {
            let i = item("Traffic: \(t.title)", #selector(chooseTraffic(_:)), checked: s.traffic == t)
            i.representedObject = t.rawValue
            skyMenu.addItem(i)
        }
        skyMenu.addItem(.separator())
        skyMenu.addItem(flagItem("Fly Over Windows", .flyOverWindows))
        let skyItem = NSMenuItem(title: "Sky", action: nil, keyEquivalent: "")
        skyItem.submenu = skyMenu
        menu.addItem(skyItem)

        // Dock
        let dockMenu = NSMenu()
        dockMenu.addItem(flagItem("Neon Outline", .dockNeon))
        if !DockLocator.hasAccessibility {
            dockMenu.addItem(.separator())
            dockMenu.addItem(item("Track Dock Precisely (Accessibility)…", #selector(askAccessibility)))
        }
        let dockItem = NSMenuItem(title: "Dock", action: nil, keyEquivalent: "")
        dockItem.submenu = dockMenu
        menu.addItem(dockItem)

        // Screen
        menu.addItem(flagItem("Corner Palm Trees", .dockPalms))
        menu.addItem(flagItem("Palms Over Windows", .palmsOverWindows))
        menu.addItem(flagItem("Dreamy Lights (flares on the wallpaper)", .dreamyLights))
        menu.addItem(flagItem("Dreamy Haze", .dreamyHaze))
        menu.addItem(flagItem("Dreamy Haze Over Apps", .hazeOverApps))
        menu.addItem(flagItem("Random Sparks", .sparks))
        menu.addItem(flagItem("Party Lights (beams & lasers)", .clubBeams))
        menu.addItem(flagItem("Party Lights Over Apps", .partyOverApps))
        menu.addItem(flagItem("Neon Screen Border", .edgeGlow))
        menu.addItem(flagItem("Minimap (bottom-left, behind windows)", .minimap))
        menu.addItem(flagItem("Compass (sun & Vice City markers)", .compass))
        menu.addItem(flagItem("Compass Over Windows", .compassOverWindows))
        if on && s.isOn(.compass) {
            let info = NSMenuItem(title: Bearings.summary(), action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
        }
        menu.addItem(.separator())

        // Music
        let radio = NSMenu()
        radio.addItem(item("Play GTA VI: The Album (Deluxe)", #selector(playAlbum)))
        radio.addItem(item("Search Apple Music: “Run Away With Me”", #selector(searchRunAway)))
        radio.addItem(.separator())
        let albumMenu = NSMenu()
        for (i, t) in LeonidaRadio.tracks.enumerated() {
            let ti = item("\(i + 1). \(t.title) — \(t.artist)", #selector(playTrack(_:)))
            ti.representedObject = t.link
            albumMenu.addItem(ti)
        }
        let albumItem = NSMenuItem(title: "The Album: Tracks", action: nil, keyEquivalent: "")
        albumItem.submenu = albumMenu
        radio.addItem(albumItem)
        let scoreMenu = NSMenu()
        for t in LeonidaRadio.score {
            let ti = item("\(t.title) — \(t.artist)", #selector(playTrack(_:)))
            ti.representedObject = t.link
            scoreMenu.addItem(ti)
        }
        let scoreItem = NSMenuItem(title: "Original Score by Justice", action: nil, keyEquivalent: "")
        scoreItem.submenu = scoreMenu
        radio.addItem(scoreItem)
        let radioItem = NSMenuItem(title: "Leonida Radio", action: nil, keyEquivalent: "")
        radioItem.submenu = radio
        menu.addItem(radioItem)
        menu.addItem(.separator())

        menu.addItem(item("Summon a Helicopter", #selector(summon), key: "h", enabled: on))
        menu.addItem(.separator())
        menu.addItem(item("Open rockstargames.com/VI", #selector(openSite)))
        menu.addItem(item("Show Downloaded Images", #selector(openCache)))
        menu.addItem(.separator())
        menu.addItem(item("Quit & Restore Desktop", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "", checked: Bool = false, enabled: Bool = true) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: enabled ? action : nil, keyEquivalent: key)
        i.target = self
        i.state = checked ? .on : .off
        return i
    }

    private func flagItem(_ title: String, _ flag: Flag) -> NSMenuItem {
        let i = item(title, #selector(toggleFlag(_:)), checked: Settings.shared.isOn(flag))
        i.representedObject = flag.rawValue
        return i
    }

    // MARK: Actions

    @objc private func toggleTheme() {
        let s = Settings.shared
        s.set(.themeOn, !s.isOn(.themeOn))
        applyTheme()
    }

    @objc private func toggleFlag(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let flag = Flag(rawValue: raw) else { return }
        let s = Settings.shared
        s.set(flag, !s.isOn(flag))
        switch flag {
        case .dreamyHaze, .hazeOverApps:
            buildHaze()
        case .viceGrade, .clubBeams, .partyOverApps, .dreamyLights:
            backdropWindows.compactMap { $0.contentView as? BackdropView }.forEach { $0.updateEffects() }
            buildPartyOverlay()
        case .flyOverWindows:
            let level: NSWindow.Level = s.isOn(.flyOverWindows) ? .skyOverWindows : .skyBehindWindows
            skyWindows.forEach { $0.level = level }
        case .dockNeon:
            dock.refresh(force: true)
        case .dockPalms, .palmsOverWindows:
            palms.rebuild()
        case .edgeGlow:
            buildEdgeGlow()
        case .minimap:
            minimap.start()
        case .lensFringe:
            wallpaper.reload()
        case .compass, .compassOverWindows:
            buildCompass()
        default:
            break   // sky flags are read each time something spawns
        }
    }

    @objc private func chooseSet(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let set = WallpaperSet(rawValue: raw) else { return }
        Settings.shared.wallpaperSet = set
        if Settings.shared.isOn(.themeOn) { wallpaper.start() }
    }

    @objc private func chooseRotation(_ sender: NSMenuItem) {
        Settings.shared.rotateMinutes = sender.tag
        wallpaper.scheduleTimer()
    }

    @objc private func chooseTraffic(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let t = Traffic(rawValue: raw) else { return }
        Settings.shared.traffic = t
        traffic.rescheduleForTrafficChange()
    }

    @objc private func nextWallpaper() { wallpaper.next() }
    @objc private func playAlbum() { NSWorkspace.shared.open(LeonidaRadio.album) }
    @objc private func searchRunAway() { LeonidaRadio.searchAppleMusic("Run Away With Me") }
    @objc private func playTrack(_ sender: NSMenuItem) {
        if let link = sender.representedObject as? String { LeonidaRadio.open(link) }
    }
    @objc private func summon() { traffic.summon() }
    @objc private func askAccessibility() { DockLocator.requestAccessibility() }
    @objc private func openSite() { NSWorkspace.shared.open(URL(string: "https://www.rockstargames.com/VI")!) }
    @objc private func openCache() { NSWorkspace.shared.open(ImageStore.shared.directory) }
    @objc private func quit() { NSApp.terminate(nil) }
}

enum Icons {
    /// Menu bar glyph: a palm under the moon (template, so it follows light/dark menu bars).
    static func statusPalm() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.translateBy(x: 6.5, y: 1)
            ctx.addPath(Shapes.palm(height: 14, lean: 0.3, fronds: 7, seed: 7))
            ctx.setFillColor(.black)
            ctx.fillPath()
            ctx.translateBy(x: -6.5, y: -1)
            ctx.fillEllipse(in: CGRect(x: 12.5, y: 12.5, width: 4, height: 4))
            return true
        }
        image.isTemplate = true
        return image
    }
}
