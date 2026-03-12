import Testing
import Foundation
@testable import lyarrics

// MARK: - Helpers

private func makeTestDatabase() throws -> (MusicDatabase, URL) {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("lyarricsTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let db = try MusicDatabase(dbPath: tempDir.appendingPathComponent("test.db").path)
    return (db, tempDir)
}

private func makeTrack(
    path: String = "/music/song.mp3",
    title: String = "Test Track",
    artist: String = "Test Artist",
    album: String = "Test Album",
    duration: Double = 180.0,
    trackNumber: Int? = 1,
    lyrics: String? = nil,
    lyricType: LyricType? = nil
) -> Track {
    Track(
        fileTrackPath: path,
        fileTrackName: URL(fileURLWithPath: path).lastPathComponent,
        fileLyricPath: nil,
        fileLyricName: nil,
        title: title,
        artist: artist,
        album: album,
        duration: duration,
        trackNumber: trackNumber,
        lyrics: lyrics,
        lyricType: lyricType,
        lastModified: Date()
    )
}

// MARK: - Tests

@Suite("MusicDatabase Tests")
struct MusicDatabaseTests {

    // MARK: Insert & Retrieve

    @Test("insertOrUpdateSong persists a track")
    func insertAndRetrieve() throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let track = makeTrack(path: "/music/song.mp3", title: "Hello")
        try db.insertOrUpdateSong(track)

        let retrieved = try db.getSongByPath("/music/song.mp3")
        #expect(retrieved != nil)
        #expect(retrieved?.title == "Hello")
        #expect(retrieved?.artist == "Test Artist")
        #expect(retrieved?.album == "Test Album")
        #expect(retrieved?.duration == 180.0)
    }

    @Test("getSongByPath returns nil for unknown path")
    func getSongByPathMissing() throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = try db.getSongByPath("/does/not/exist.mp3")
        #expect(result == nil)
    }

    @Test("insertOrUpdateSong replaces on duplicate path")
    func insertOrUpdateReplaces() throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let original = makeTrack(path: "/music/song.mp3", title: "Original")
        try db.insertOrUpdateSong(original)

        let updated = makeTrack(path: "/music/song.mp3", title: "Updated")
        try db.insertOrUpdateSong(updated)

        let retrieved = try db.getSongByPath("/music/song.mp3")
        #expect(retrieved?.title == "Updated")
    }

    @Test("insertOrUpdateSongs batch inserts multiple tracks")
    func batchInsert() throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tracks = [
            makeTrack(path: "/music/a.mp3", title: "Track A"),
            makeTrack(path: "/music/b.mp3", title: "Track B"),
            makeTrack(path: "/music/c.mp3", title: "Track C"),
        ]
        try db.insertOrUpdateSongs(tracks)

        let all = try db.getAllSongs()
        #expect(all.count == 3)
    }

    @Test("getAllSongs returns all inserted tracks")
    func getAllSongs() throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try db.insertOrUpdateSong(makeTrack(path: "/music/a.mp3"))
        try db.insertOrUpdateSong(makeTrack(path: "/music/b.mp3"))

        let all = try db.getAllSongs()
        #expect(all.count == 2)
    }

    @Test("getAllSongs returns empty when database is empty")
    func getAllSongsEmpty() throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let all = try db.getAllSongs()
        #expect(all.isEmpty)
    }

    // MARK: Lyrics Updates

    @Test("updateSongLyrics sets synced lyrics")
    func updateSongLyricsSetsSynced() throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let path = "/music/song.mp3"
        try db.insertOrUpdateSong(makeTrack(path: path))

        let lyricsContent = "[00:16.41] Hello\n[00:20.00] World"
        try db.updateSongLyrics(
            trackPath: path,
            lyricsContent: lyricsContent,
            lyricType: .synced,
            lyricPath: "/music/song.lrc",
            lyricName: "song.lrc"
        )

        let updated = try db.getSongByPath(path)
        #expect(updated?.lyrics == lyricsContent)
        #expect(updated?.lyricType == .synced)
        #expect(updated?.fileLyricPath == "/music/song.lrc")
        #expect(updated?.fileLyricName == "song.lrc")
    }

    @Test("updateSongLyrics marks track as instrumental")
    func updateSongLyricsInstrumental() throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let path = "/music/song.mp3"
        try db.insertOrUpdateSong(makeTrack(path: path))

        try db.updateSongLyrics(
            trackPath: path,
            lyricsContent: nil,
            lyricType: .instrumental,
            lyricPath: nil,
            lyricName: nil
        )

        let updated = try db.getSongByPath(path)
        #expect(updated?.lyricType == .instrumental)
        #expect(updated?.lyrics == nil)
    }

    // MARK: Songs Needing Lyrics

    @Test("getSongsNeedingLyrics returns tracks without synced lyrics")
    func getSongsNeedingLyricsNoSynced() throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Track with no lyrics at all
        let noLyrics = makeTrack(path: "/music/a.mp3", lyrics: nil)
        // Track with plain (unsynced) lyrics
        let plainLyrics = makeTrack(path: "/music/b.mp3", lyrics: "Hello world", lyricType: .plain)
        // Track with synced lyrics — should NOT appear
        let syncedLyrics = makeTrack(path: "/music/c.mp3", lyrics: "[00:01.00] Hi", lyricType: .synced)
        // Track with instrumental music, not lyrics - should NOT appear
        let instrumentalLyrics = makeTrack(path: "/music/d.mp3", lyrics: nil, lyricType: .instrumental)

        try db.insertOrUpdateSongs([noLyrics, plainLyrics, syncedLyrics, instrumentalLyrics])

        let needing = try db.getSongsNeedingLyrics()
        let paths = needing.map(\.fileTrackPath)
        #expect(paths.contains("/music/a.mp3"))
        #expect(paths.contains("/music/b.mp3"))
        #expect(!paths.contains("/music/c.mp3"))
        #expect(!paths.contains("/music/d.mp3"))
    }

    @Test("getSongsNeedingLyrics returns empty when all tracks have synced lyrics")
    func getSongsNeedingLyricsAllSynced() throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let synced = makeTrack(path: "/music/a.mp3", lyrics: "[00:01.00] Hi", lyricType: .synced)
        try db.insertOrUpdateSong(synced)

        let needing = try db.getSongsNeedingLyrics()
        #expect(needing.isEmpty)
    }

    // MARK: Search

    @Test("searchLyrics returns tracks matching lyric content")
    func searchLyricsMatch() throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let matching = makeTrack(path: "/music/a.mp3", lyrics: "Is this the real life?")
        let nonMatching = makeTrack(path: "/music/b.mp3", lyrics: "Some other lyrics")
        try db.insertOrUpdateSongs([matching, nonMatching])

        let results = try db.searchLyrics(query: "real life")
        #expect(results.count == 1)
        #expect(results.first?.fileTrackPath == "/music/a.mp3")
    }

    @Test("searchLyrics returns empty when no match")
    func searchLyricsNoMatch() throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try db.insertOrUpdateSong(makeTrack(path: "/music/a.mp3", lyrics: "Some lyrics"))

        let results = try db.searchLyrics(query: "xyz not found")
        #expect(results.isEmpty)
    }

    @Test("searchLyrics is case-insensitive via SQL LIKE")
    func searchLyricsCaseSensitivity() throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try db.insertOrUpdateSong(makeTrack(path: "/music/a.mp3", lyrics: "Hello World"))

        // SQLite LIKE is case-insensitive for ASCII
        let results = try db.searchLyrics(query: "hello world")
        #expect(results.count == 1)
    }

    // MARK: Paths and Dates

    @Test("getAllPathsAndDates returns path to date mapping")
    func getAllPathsAndDates() throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let now = Date()
        let track = Track(
            fileTrackPath: "/music/song.mp3",
            fileTrackName: "song.mp3",
            fileLyricPath: nil,
            fileLyricName: nil,
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 120.0,
            trackNumber: nil,
            lyrics: nil,
            lyricType: nil,
            lastModified: now
        )
        try db.insertOrUpdateSong(track)

        let pathsAndDates = try db.getAllPathsAndDates()
        #expect(pathsAndDates["/music/song.mp3"] != nil)
    }

    @Test("getAllPathsAndDates returns empty for empty database")
    func getAllPathsAndDatesEmpty() throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = try db.getAllPathsAndDates()
        #expect(result.isEmpty)
    }

    // MARK: Track optional fields

    @Test("Track stores optional trackNumber")
    func trackOptionalTrackNumber() throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let withNumber = makeTrack(path: "/music/a.mp3", trackNumber: 5)
        let withoutNumber = makeTrack(path: "/music/b.mp3", trackNumber: nil)
        try db.insertOrUpdateSongs([withNumber, withoutNumber])

        let a = try db.getSongByPath("/music/a.mp3")
        let b = try db.getSongByPath("/music/b.mp3")
        #expect(a?.trackNumber == 5)
        #expect(b?.trackNumber == nil)
    }
}

// MARK: - Nil database guard tests

@Suite("MusicDatabase nil-connection guard tests")
struct MusicDatabaseNilTests {

    @Test("insertOrUpdateSong is a no-op when db is nil")
    func insertOrUpdateSongNilDB() throws {
        let db = MusicDatabase(nilDatabase: ())
        try db.insertOrUpdateSong(makeTrack())
        // No throw and no crash — guard returned early
    }

    @Test("insertOrUpdateSongs is a no-op when db is nil")
    func insertOrUpdateSongsNilDB() throws {
        let db = MusicDatabase(nilDatabase: ())
        try db.insertOrUpdateSongs([makeTrack(path: "/a.mp3"), makeTrack(path: "/b.mp3")])
    }

    @Test("getAllSongs returns empty array when db is nil")
    func getAllSongsNilDB() throws {
        let db = MusicDatabase(nilDatabase: ())
        let result = try db.getAllSongs()
        #expect(result.isEmpty)
    }

    @Test("getSongByPath returns nil when db is nil")
    func getSongByPathNilDB() throws {
        let db = MusicDatabase(nilDatabase: ())
        let result = try db.getSongByPath("/music/song.mp3")
        #expect(result == nil)
    }

    @Test("searchLyrics returns empty array when db is nil")
    func searchLyricsNilDB() throws {
        let db = MusicDatabase(nilDatabase: ())
        let result = try db.searchLyrics(query: "hello")
        #expect(result.isEmpty)
    }

    @Test("getSongsNeedingLyrics returns empty array when db is nil")
    func getSongsNeedingLyricsNilDB() throws {
        let db = MusicDatabase(nilDatabase: ())
        let result = try db.getSongsNeedingLyrics()
        #expect(result.isEmpty)
    }

    @Test("updateSongLyrics is a no-op when db is nil")
    func updateSongLyricsNilDB() throws {
        let db = MusicDatabase(nilDatabase: ())
        try db.updateSongLyrics(
            trackPath: "/music/song.mp3",
            lyricsContent: "Hello",
            lyricType: .synced,
            lyricPath: "/music/song.lrc",
            lyricName: "song.lrc"
        )
    }

    @Test("getAllPathsAndDates returns empty dictionary when db is nil")
    func getAllPathsAndDatesNilDB() throws {
        let db = MusicDatabase(nilDatabase: ())
        let result = try db.getAllPathsAndDates()
        #expect(result.isEmpty)
    }
}
