import CoreGraphics

/// Colours sampled from rockstargames.com/VI (site background, the "Out Now" banner and
/// the Vice City sunset), plus neon accents taken from the official night screenshots.
enum Palette {
    static let siteNavyTop: UInt32 = 0x19192e
    static let siteNavyBottom: UInt32 = 0x101120
    static let lavender: UInt32 = 0x9b95c9
    static let palmSlate: UInt32 = 0x354363
    static let birdSlate: UInt32 = 0x5d6493
    static let skyViolet: UInt32 = 0x6d66b4
    static let skyLilac: UInt32 = 0x8878b2
    static let skyMauve: UInt32 = 0xab8898
    static let skyPeach: UInt32 = 0xc38975
    static let skyEmber: UInt32 = 0xc86d5e
    static let artPink: UInt32 = 0xd78dab
    static let artRed: UInt32 = 0xaf5361

    static let neonPink: UInt32 = 0xff4fa3
    static let neonViolet: UInt32 = 0xa678ff
    static let neonCyan: UInt32 = 0x4fe0ff
    static let warmWindow: UInt32 = 0xffd59a
    static let coolWindow: UInt32 = 0xb4ccff
    static let silhouette: UInt32 = 0x0b0a17

    static func c(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
                green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255,
                alpha: alpha)
    }
}

/// Small deterministic random generator so generated scenery is stable between launches.
struct RNG {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }
    mutating func r(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * CGFloat(next()) }
    mutating func chance(_ p: Double) -> Bool { next() < p }
    mutating func pick<T>(_ items: [T]) -> T { items[min(items.count - 1, Int(next() * Double(items.count)))] }
}
