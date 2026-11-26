import Foundation

/// One official image served by rockstargames.com/VI (Media → Screenshots / Artwork & Wallpapers).
struct Shot: Hashable {
    let file: String   // e.g. "Vice_City_27.0d2e~w_r93hmh" (the site's hashed static file name)

    var name: String { String(file.split(separator: ".").first ?? Substring(file)) }
    var title: String {
        name.replacingOccurrences(of: "_landscape", with: "").replacingOccurrences(of: "_", with: " ")
    }
    var remoteURL: URL { URL(string: "https://www.rockstargames.com/VI/_next/static/media/\(file).jpg")! }
    var cacheFileName: String { name + ".jpg" }
}

enum WallpaperSet: String, CaseIterable {
    case downtown, viceNights, nightlife, sunsetArt, liveSkyline, mix

    var title: String {
        switch self {
        case .downtown: "Downtown Vice City (default)"
        case .viceNights: "Vice City Nights"
        case .nightlife: "Nightlife"
        case .sunsetArt: "Sunset Artwork"
        case .liveSkyline: "Neon Skyline (live, generated)"
        case .mix: "Shuffle Everything"
        }
    }
}

enum Catalog {
    /// The default: the downtown skyline over the river at night, on its own.
    static let downtown: [Shot] = [Shot(file: "Vice_City_27.0d2e~w_r93hmh")]

    /// Night / dusk city shots: skylines, neon, the harbour.
    static let viceNights: [Shot] = [
        "Vice_City_27.0d2e~w_r93hmh",
        "Vice_City_08.0bbg_xp4hqdvz",
        "Vice_City_17.0er79m2u3nygs",
        "Vice_City_22.0--9jlb822n~g",
        "Vice_City_11.09paum3g942sc",
        "Vice_City_01.135x56yoeu.6t",
        "Port_Gellhorn_01.0fmisvza-5-cq",
        "Port_Gellhorn_04.0hd-7kzfi51q.",
        "Ambrosia_02.0wtqs05ozl.ym",
    ].map(Shot.init(file:))

    /// Clubs, studios and neon-lit interiors.
    static let nightlife: [Shot] = [
        "Vice_City_13.0iq8ff474tsdx",
        "DreQuan_Priest_02.02u69e~nkk3eo",
        "Vice_City_06.0_tdmr3u9w84x",
        "DreQuan_Priest_03.0zbl4i_x_1biu",
        "Boobie_Ike_02.0sp9mtc.1cdzs",
        "Real_Dimez_04.0wa3vo07lz4e2",
        "Vice_City_25.0f72z-5qgyd~v",
        "DreQuan_Priest_01.0_0~wi-ipdj35",
        "Real_Dimez_02.1366u9.x.yp0_",
        "Vice_City_20.18c75478u52nf",
    ].map(Shot.init(file:))

    /// The official illustrated key art: the purple / peach palette of the website.
    static let sunsetArt: [Shot] = [
        "Jason_Lucia_Rooftop_landscape.0c6p5do~-8~7.",
        "Jason_and_Lucia_Beach_landscape.0419q._86ukpt",
        "Jason_and_Lucia_02_landscape.0cosv-uzbpt91",
        "The_Album_Cover_Art_landscape.000ifb9a.j-gp",
        "Jason_and_Lucia_01_landscape.12x2gvspcm_3m",
        "Jason_and_Lucia_Robbery_landscape.09c8a~do21h4p",
        "Jason_and_Lucia_Motel_landscape.08edvuwtm-20v",
        "Jason_Lucia_Lock_And_Load_landscape.0l9s5w7ih9p~3",
    ].map(Shot.init(file:))

    static func shots(for set: WallpaperSet) -> [Shot] {
        switch set {
        case .downtown: downtown
        case .viceNights: viceNights
        case .nightlife: nightlife
        case .sunsetArt: sunsetArt
        case .liveSkyline: []
        case .mix: interleave([viceNights, nightlife, sunsetArt])
        }
    }

    private static func interleave(_ lists: [[Shot]]) -> [Shot] {
        var out: [Shot] = []
        for i in 0..<(lists.map(\.count).max() ?? 0) {
            for l in lists where i < l.count { out.append(l[i]) }
        }
        return out
    }

    /// Lines from the official "Only in Leonida" page.
    static let quotes: [(String, String)] = [
        ("Another day in paradise, right?", "Jason Duval"),
        ("If anything happens, I'm right behind you.", "Jason Duval"),
        ("The only thing that matters is who you know and what you got.", "Lucia Caminos"),
        ("There are way too many birds flying around in perfect formation.", "Cal Hampton"),
        ("It's all about heart — the Jack of Hearts.", "Boobie Ike"),
        ("Dancers are like my A&Rs.", "Dre'Quan Priest"),
        ("One hit away from fame.", "Real Dimez"),
        ("Life is full of surprises, my friend.", "Raul Bautista"),
        ("Nothing better than a Mudslide at sunset.", "Brian Heder"),
        ("When the sun fades and the neon glows, everyone has something to gain.", "Only in Leonida"),
    ]
}
