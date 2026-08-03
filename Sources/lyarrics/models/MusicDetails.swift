struct MusicDetails {
    public var songs: Int
    public var lyrics: Int
    public var plain: Int
    public var sync: Int
    public var instrumental: Int
    public var missing: Int
    public var notFound: Int
    public var noLyricsAvailable: Int

    public func show() {
        let rows: [(String, Int)] = [
            ("Songs", songs), ("Lyrics", lyrics),
            ("Missing", missing), ("Synced", sync),
            ("Plain", plain), ("Instrumental", instrumental),
            ("Not Found on LRCLIB", notFound),
            ("No Lyrics Available", noLyricsAvailable),
        ]
        print("Music Lyrics Details")
        print(String(repeating: "-", count: 25))
        for (label, value) in rows { print("\(label): \(value)") }
    }
}
