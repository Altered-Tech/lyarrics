public struct Record {
    public var id: Int
    public var trackName: String
    public var albumName: String
    public var artistName: String
    public var instrumental: Bool
    public var plainLyrics: String?
    public var syncedLyrics: String?

    internal init(from source: Components.Schemas.Record) {
        self.id = source.id
        self.trackName = source.trackName
        self.albumName = source.albumName
        self.artistName = source.artistName
        self.instrumental = source.instrumental
        self.plainLyrics = source.plainLyrics
        self.syncedLyrics = source.syncedLyrics
    }
}