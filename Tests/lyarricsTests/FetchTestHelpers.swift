import Foundation
@testable import lyarrics

// All helpers in this file intentionally omit `import LRCLib` so that
// the `Track` type is unambiguous (lyarrics.Track, not LRCLib.Track).

func makeLyarricsTrack(
    fileTrackPath: String = "/music/bohemian_rhapsody.flac",
    title: String = "Bohemian Rhapsody",
    artist: String = "Queen",
    album: String = "A Night at the Opera",
    duration: Double = 354.0
) -> Track {
    Track(
        fileTrackPath: fileTrackPath,
        fileTrackName: URL(fileURLWithPath: fileTrackPath).lastPathComponent,
        fileLyricPath: nil,
        fileLyricName: nil,
        title: title,
        artist: artist,
        album: album,
        duration: duration,
        trackNumber: nil,
        lyrics: nil,
        instrumental: false,
        isSyncedLyrics: false,
        lastModified: Date()
    )
}

/// Creates a temp directory with a database seeded with `count` tracks whose
/// file paths live inside the temp dir (so `.lrc` files can be written there).
/// Returns a `Fetch` configured for serial (concurrency=1), zero-delay processing.
func makeFetchTestSetup(count: Int = 1) throws -> (fetch: Fetch, database: MusicDatabase, tempDir: URL, tracks: [Track]) {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("FetchRunTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let db = try MusicDatabase(dbPath: tempDir.appendingPathComponent("test.db").path)

    var tracks: [Track] = []
    for i in 0..<count {
        let trackPath = tempDir.appendingPathComponent("track\(i).flac").path
        let track = makeLyarricsTrack(fileTrackPath: trackPath)
        try db.insertOrUpdateSong(track)
        tracks.append(track)
    }

    var fetch = Fetch()
    fetch.path = tempDir.path
    fetch.delay = 0
    fetch.concurrency = 1
    fetch.maxRetries = 1
    fetch.dryRun = false
    fetch.scan = false

    return (fetch, db, tempDir, tracks)
}
