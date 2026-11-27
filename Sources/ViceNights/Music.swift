import AppKit

/// "Run Away With Me", the song from the GTA VI trailer. Nothing is downloaded or bundled:
/// each link opens the track in that service.
enum LeonidaRadio {
    static let songTitle = "Run Away With Me"

    static let links: [(service: String, url: URL)] = [
        ("Apple Music", URL(string: "https://music.apple.com/in/album/run-away-with-me/1442810070?i=1442810074")!),
        ("Spotify", URL(string: "https://open.spotify.com/track/3rLLDjCJ9JllYvwUKfd3vW")!),
        ("YouTube", URL(string: "https://youtu.be/TeccAtqd5K8")!),
    ]
}
