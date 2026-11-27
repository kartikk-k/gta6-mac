import Foundation

enum Flag: String, CaseIterable {
    case themeOn, viceGrade, clubBeams, drift, edgeGlow, partyOverApps, dreamyLights, dreamyHaze, hazeOverApps, sparks
    case helicopters, searchlights, birds, jets, flyOverWindows
    case dockNeon, dockPalms, palmsOverWindows
    case compass, compassOverWindows, minimap, lensFringe
}

enum Traffic: String, CaseIterable {
    case calm, normal, busy
    var title: String {
        switch self {
        case .calm: "Calm"
        case .normal: "Normal"
        case .busy: "Busy night"
        }
    }
    /// Seconds between sky events.
    var gap: ClosedRange<Double> {
        switch self {
        case .calm: 50...100
        case .normal: 25...55
        case .busy: 10...22
        }
    }
}

@MainActor
final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    func isOn(_ f: Flag) -> Bool { d.object(forKey: f.rawValue) as? Bool ?? (f != .drift && f != .partyOverApps && f != .jets) }
    func set(_ f: Flag, _ value: Bool) { d.set(value, forKey: f.rawValue) }

    var wallpaperSet: WallpaperSet {
        get { WallpaperSet(rawValue: d.string(forKey: "wallpaperSet") ?? "") ?? .downtown }
        set { d.set(newValue.rawValue, forKey: "wallpaperSet") }
    }
    var traffic: Traffic {
        get { Traffic(rawValue: d.string(forKey: "traffic") ?? "") ?? .normal }
        set { d.set(newValue.rawValue, forKey: "traffic") }
    }
    /// 0 = never rotate.
    var rotateMinutes: Int {
        get { d.object(forKey: "rotateMinutes") as? Int ?? 0 }
        set { d.set(newValue, forKey: "rotateMinutes") }
    }
    /// Set the first time a song link is opened; until then the menu offers it at the top.
    var hasPlayedMusic: Bool {
        get { d.bool(forKey: "hasPlayedMusic") }
        set { d.set(newValue, forKey: "hasPlayedMusic") }
    }
    var askedForAccessibility: Bool {
        get { d.bool(forKey: "askedForAccessibility") }
        set { d.set(newValue, forKey: "askedForAccessibility") }
    }
}
