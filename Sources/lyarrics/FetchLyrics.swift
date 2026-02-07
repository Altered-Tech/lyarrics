// import LRCLib

// struct Lyrics {
//     func fetch() async throws {
//         let lrc = LRCLibClient()
//         let song: Song = .init(
//             track: Track.init("Sink into me"), 
//             artist: Artist.init("Wind Walkers"), 
//             album: Album.init("I dont belong here"), 
//             duration: Duration.init(173))
//         do {
//             let lyrics: Record = try await lrc.getLyrics(song: song)
//             print("\(lyrics.id): \(lyrics.artistName) - \(lyrics.albumName) - \(lyrics.trackName)")
//             print("Intrumental: \(lyrics.instrumental.description)")
//             if let plainLyrics = lyrics.plainLyrics {
//                 print("Plain lyrics: \(plainLyrics)")
//             }

//             if let syncLyrics = lyrics.syncedLyrics {
//                 print("Synced Lyrics: \(syncLyrics)")
//             }
//         } catch LRCError.notFound(_) {
//             print("Song not found")
//         } catch LRCError.undocumented(let code, _){
//             print("unknown code \(code)")
//         }
//     }
// }