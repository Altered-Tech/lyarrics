import ArgumentParser
import LRCLib

struct Search: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Search lrc Lib lyrics from the command line"
    )

    @Argument(help: "Artist")
    var artist: String

    @Argument(help: "Album")
    var album: String

    @Argument(help: "Track")
    var track: String

    @Argument(help: "Duration")
    var duration: Int

    func run() async throws {
        let lrc = LRCLibClient()
        let song = Song(
            track: LRCLib.Track(track), 
            artist: Artist(artist), 
            album: Album(album), 
            duration: Duration(duration))
        do {
            let result = try await lrc.getLyrics(song: song)
            print(result)
        } catch {
            print("\(error)")
        }
    }
}
