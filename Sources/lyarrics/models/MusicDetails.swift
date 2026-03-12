struct MusicDetails {
    public var songs: Int
    public var lyrics: Int
    public var plain: Int
    public var sync: Int
    public var instrumental: Int
    public var missing: Int

    public func show() {
        let rows: [(String, Int)] = [
            ("Songs", songs), ("Lyrics", lyrics),
            ("Missing", missing), ("Synced", sync),
            ("Plain", plain), ("Instrumental", instrumental),
        ]
        print("Music Lyrics Details")
        print(String(repeating: "-", count: 25))
        for (label, value) in rows { print("\(label): \(value)") }
    }
}