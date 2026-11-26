import AppKit

/// Official GTA VI music, exactly as listed on rockstargames.com/VI/music. Rockstar offers
/// no audio files, only "Play Full Track" links that open your streaming service, so that's
/// what these do. Nothing is downloaded or bundled.
enum LeonidaRadio {
    struct Track { let title: String; let artist: String; let link: String }

    static let album = URL(string: "https://gtavi-thealbum.lnk.to/deluxeedition")!

    static let tracks: [Track] = [
        Track(title: "Starting from Zero (feat. Michael McDonald)", artist: "Justice", link: "http://justice.lnk.to/startingfromzero"),
        Track(title: "That's It (feat. Future & Metro Boomin)", artist: "Yung Lean", link: "https://gtavi-thealbum.lnk.to/thatsit"),
        Track(title: "AHH YEA", artist: "Playboi Carti", link: "https://gtavi-thealbum.lnk.to/ahhyea"),
        Track(title: "RHYNO", artist: "Travis Scott", link: "https://gtavi-thealbum.lnk.to/rhyno"),
        Track(title: "Sexy Magic", artist: "CA7RIEL & Paco Amoroso, Pink Pantheress, Fred again.. & Etienne de Crécy", link: "https://gtavi-thealbum.lnk.to/sexymagic"),
        Track(title: "Flower in a Hurricane", artist: "Justice", link: "https://gtavi-thealbum.lnk.to/fiah"),
        Track(title: "Go Easy", artist: "Dua Lipa", link: "https://gtavi-thealbum.lnk.to/goeasy"),
        Track(title: "Last Thing You Need", artist: "Morgan Wallen", link: "https://gtavi-thealbum.lnk.to/lastthingyouneed"),
        Track(title: "X", artist: "JHAYCO", link: "https://gtavi-thealbum.lnk.to/XGTAVI"),
        Track(title: "Suzuki", artist: "Fuerza Regida", link: "http://gtavi-thealbum.lnk.to/suzuki"),
        Track(title: "Macacoa 2000", artist: "Rauw Alejandro", link: "https://gtavi-thealbum.lnk.to/macacoa2000"),
        Track(title: "Dance with Me (feat. elkan)", artist: "A Boogie Wit da Hoodie", link: "https://gtavi-thealbum.lnk.to/dancewithme"),
        Track(title: "Bigger", artist: "Burna Boy", link: "https://gtavi-thealbum.lnk.to/bigger"),
        Track(title: "COUNT UP", artist: "Gunna", link: "https://gtavi-thealbum.lnk.to/countup"),
        Track(title: "Let's Rock", artist: "Kodak Black & Don Toliver", link: "https://gtavi-thealbum.lnk.to/letsrock"),
        Track(title: "WAKIN UP FLEX", artist: "Young Thug", link: "https://gtavi-thealbum.lnk.to/wakingupflex"),
        Track(title: "IKYFL", artist: "Tee Grizzley", link: "https://gtavi-thealbum.lnk.to/IKYFL"),
        Track(title: "TF?", artist: "Don Toliver", link: "https://gtavi-thealbum.lnk.to/DTTF"),
        Track(title: "Don't Chart", artist: "Cardi B", link: "http://gtavi-thealbum.lnk.to/dontchart"),
        Track(title: "GMA", artist: "JT", link: "https://gtavi-thealbum.lnk.to/GMA"),
        Track(title: "Power Trip", artist: "JENNIE", link: "https://gtavi-thealbum.lnk.to/powertrip"),
        Track(title: "Blood In Your Eyes", artist: "Tove Lo", link: "https://gtavi-thealbum.lnk.to/bloodinyoureyes"),
        Track(title: "Fast Emotion", artist: "Zara Larsson", link: "https://gtavi-thealbum.lnk.to/fastemotion"),
        Track(title: "Sweet Like Candy", artist: "Camila Cabello", link: "https://gtavi-thealbum.lnk.to/sweetlikecandy"),
        Track(title: "Only One", artist: "Fcukers", link: "https://gtavi-thealbum.lnk.to/onlyone"),
        Track(title: "Sandunguea", artist: "Arca", link: "https://gtavi-thealbum.lnk.to/sandungeau"),
        Track(title: "TRDWFE", artist: "Rina Sawayama", link: "https://gtavi-thealbum.lnk.to/TRDWFE"),
        Track(title: "All Again", artist: "Rose Gray", link: "https://gtavi-thealbum.lnk.to/allagain"),
        Track(title: "Crazy for You", artist: "Lana Del Rey", link: "https://gtavi-thealbum.lnk.to/crazyforyou"),
        Track(title: "Largate", artist: "Kali Uchis & Helado Negro", link: "https://gtavi-thealbum.lnk.to/largate"),
        Track(title: "NO ME BUSQUES", artist: "Omar Apollo", link: "https://gtavi-thealbum.lnk.to/nomebusques"),
        Track(title: "Bright Lights, Big City", artist: "Keith Richards", link: "https://gtavi-thealbum.lnk.to/brightlightsbigcity"),
        Track(title: "Stone Kold Krazy Luuv", artist: "Jesse Johnson & DāM-FunK", link: "https://gtavi-thealbum.lnk.to/stonekoldkrazyluuv"),
        Track(title: "Overtown Lights", artist: "Stanley Clarke, Yussef Dayes & Robert Glasper", link: "https://gtavi-thealbum.lnk.to/overtownlights"),
        Track(title: "Burn This Shit Down", artist: "Travis Scott", link: "https://gtavi-thealbum.lnk.to/BTSD"),
        Track(title: "INTERNET $TAR", artist: "Slayyyter", link: "https://gtavi-thealbum.lnk.to/internetstar"),
        Track(title: "Interesting", artist: "The Dare", link: "https://gtavi-thealbum.lnk.to/interesting"),
        Track(title: "Touch & Go", artist: "Anitta", link: "https://gtavi-thealbum.lnk.to/touchandgo"),
        Track(title: "I JUST CAME TO POP IT", artist: "Offset", link: "https://gtavi-thealbum.lnk.to/IJCTPI"),
        Track(title: "RCKSTRL!VING", artist: "HXG, tana & Quavo", link: "https://gtavi-thealbum.lnk.to/RCKSTRLIVING"),
        Track(title: "Cookin", artist: "21 Savage", link: "https://gtavi-thealbum.lnk.to/cookin"),
        Track(title: "Got Dat", artist: "Pooh Shiesty", link: "https://gtavi-thealbum.lnk.to/gotdat"),
        Track(title: "Don Da Da", artist: "Young Nudy", link: "https://gtavi-thealbum.lnk.to/dondada"),
        Track(title: "CASHOUT", artist: "SoFaygo", link: "https://gtavi-thealbum.lnk.to/cashout"),
        Track(title: "Cooties (Remix)", artist: "Real Dimez x Sexyy Red", link: "https://gtavi-thealbum.lnk.to/cooties"),
        Track(title: "50 Bands (feat. Flo Milli)", artist: "Latto", link: "https://gtavi-thealbum.lnk.to/50bands"),
        Track(title: "Tèt Kale Bobis", artist: "Kodak Black & Michaël Brun", link: "https://gtavi-thealbum.lnk.to/tkb"),
        Track(title: "FLA Flow (feat. 454)", artist: "Denzel Curry", link: "https://gtavi-thealbum.lnk.to/FLAFlow"),
        Track(title: "You Move Me", artist: "NEIL FRANCES", link: "https://gtavi-thealbum.lnk.to/youmoveme"),
        Track(title: "Don't Play Around", artist: "CHRIS STASSY & KETTAMA", link: "https://gtavi-thealbum.lnk.to/dontplayaround"),
        Track(title: "NIGHTMARE", artist: "HEALTH", link: "https://gtavi-thealbum.lnk.to/nightmare"),
        Track(title: "Mutual Death Warrant", artist: "Power Trip", link: "https://gtavi-thealbum.lnk.to/mdw"),
        Track(title: "Granforma", artist: "Overmono", link: "https://gtavi-thealbum.lnk.to/granforma"),
        Track(title: "Windsor Drop", artist: "Overmono", link: "https://gtavi-thealbum.lnk.to/windsordrop"),
        Track(title: "Eighty Eight Comet", artist: "Overmono", link: "https://gtavi-thealbum.lnk.to/eightyeightcomet"),
        Track(title: "Banshee", artist: "Overmono", link: "https://gtavi-thealbum.lnk.to/banshee"),
        Track(title: "Welcome to Leonida", artist: "Overmono", link: "https://gtavi-thealbum.lnk.to/welcometoleonida"),
    ]

    static let score: [Track] = [
        Track(title: "Pusher (feat. Gesaffelstein)", artist: "Justice", link: "http://justice.lnk.to/pusher"),
        Track(title: "Flower in a Hurricane", artist: "Justice", link: "https://justice.lnk.to/flowerinahurricane"),
        Track(title: "Starting from Zero", artist: "Justice", link: "http://justice.lnk.to/startingfromzero"),
    ]

    static func open(_ link: String) {
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }

    /// Search the Music app (Apple Music catalogue) for something that isn't on the official album.
    static func searchAppleMusic(_ term: String) {
        let q = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? term
        if let url = URL(string: "music://music.apple.com/search?term=\(q)") { NSWorkspace.shared.open(url) }
    }
}
