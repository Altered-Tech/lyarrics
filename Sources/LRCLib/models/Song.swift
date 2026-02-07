
public struct Song {
    public let track: Track
    public let artist: Artist
    public let album: Album
    public let duration: Duration

    public init(track: Track, artist: Artist, album: Album, duration: Duration) {
        self.track = track
        self.artist = artist
        self.album = album
        self.duration = duration
    }
}