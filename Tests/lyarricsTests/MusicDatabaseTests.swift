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
    func insertAndRetrieve() async throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let track = makeTrack(path: "/music/song.mp3", title: "Hello")
        try await db.insertOrUpdateSong(track)

        let retrieved = try await db.getSongByPath("/music/song.mp3")
        #expect(retrieved != nil)
        #expect(retrieved?.title == "Hello")
        #expect(retrieved?.artist == "Test Artist")
        #expect(retrieved?.album == "Test Album")
        #expect(retrieved?.duration == 180.0)
    }

    @Test("getSongByPath returns nil for unknown path")
    func getSongByPathMissing() async throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = try await db.getSongByPath("/does/not/exist.mp3")
        #expect(result == nil)
    }

    @Test("insertOrUpdateSong replaces on duplicate path")
    func insertOrUpdateReplaces() async throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let original = makeTrack(path: "/music/song.mp3", title: "Original")
        try await db.insertOrUpdateSong(original)

        let updated = makeTrack(path: "/music/song.mp3", title: "Updated")
        try await db.insertOrUpdateSong(updated)

        let retrieved = try await db.getSongByPath("/music/song.mp3")
        #expect(retrieved?.title == "Updated")
    }

    @Test("insertOrUpdateSongs batch inserts multiple tracks")
    func batchInsert() async throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tracks = [
            makeTrack(path: "/music/a.mp3", title: "Track A"),
            makeTrack(path: "/music/b.mp3", title: "Track B"),
            makeTrack(path: "/music/c.mp3", title: "Track C"),
        ]
        try await db.insertOrUpdateSongs(tracks)

        let all = try await db.getAllSongs()
        #expect(all.count == 3)
    }

    @Test("getAllSongs returns all inserted tracks")
    func getAllSongs() async throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await db.insertOrUpdateSong(makeTrack(path: "/music/a.mp3"))
        try await db.insertOrUpdateSong(makeTrack(path: "/music/b.mp3"))

        let all = try await db.getAllSongs()
        #expect(all.count == 2)
    }

    @Test("getAllSongs returns empty when database is empty")
    func getAllSongsEmpty() async throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let all = try await db.getAllSongs()
        #expect(all.isEmpty)
    }

    // MARK: Lyrics Updates

    @Test("updateSongLyrics sets synced lyrics")
    func updateSongLyricsSetsSynced() async throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let path = "/music/song.mp3"
        try await db.insertOrUpdateSong(makeTrack(path: path))

        let lyricsContent = "[00:16.41] Hello\n[00:20.00] World"
        try await db.updateSongLyrics(
            trackPath: path,
            lyricsContent: lyricsContent,
            lyricType: .synced,
            lyricPath: "/music/song.lrc",
            lyricName: "song.lrc"
        )

        let updated = try await db.getSongByPath(path)
        #expect(updated?.lyrics == lyricsContent)
        #expect(updated?.lyricType == .synced)
        #expect(updated?.fileLyricPath == "/music/song.lrc")
        #expect(updated?.fileLyricName == "song.lrc")
    }

    @Test("updateSongLyrics marks track as instrumental")
    func updateSongLyricsInstrumental() async throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let path = "/music/song.mp3"
        try await db.insertOrUpdateSong(makeTrack(path: path))

        try await db.updateSongLyrics(
            trackPath: path,
            lyricsContent: nil,
            lyricType: .instrumental,
            lyricPath: nil,
            lyricName: nil
        )

        let updated = try await db.getSongByPath(path)
        #expect(updated?.lyricType == .instrumental)
        #expect(updated?.lyrics == nil)
    }

    // MARK: Songs Needing Lyrics

    @Test("getSongsNeedingLyrics defaults to only truly-missing tracks, excluding plain lyrics")
    func getSongsNeedingLyricsNoSynced() async throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Track with no lyrics at all
        let noLyrics = makeTrack(path: "/music/a.mp3", lyrics: nil)
        // Track with plain (unsynced) lyrics — should NOT appear by default (avoid re-fetching forever)
        let plainLyrics = makeTrack(path: "/music/b.mp3", lyrics: "Hello world", lyricType: .plain)
        // Track with synced lyrics — should NOT appear
        let syncedLyrics = makeTrack(path: "/music/c.mp3", lyrics: "[00:01.00] Hi", lyricType: .synced)
        // Track with instrumental music, not lyrics - should NOT appear
        let instrumentalLyrics = makeTrack(path: "/music/d.mp3", lyrics: nil, lyricType: .instrumental)

        try await db.insertOrUpdateSongs([noLyrics, plainLyrics, syncedLyrics, instrumentalLyrics])

        let needing = try await db.getSongsNeedingLyrics()
        let paths = needing.map(\.fileTrackPath)
        #expect(paths.contains("/music/a.mp3"))
        #expect(!paths.contains("/music/b.mp3"))
        #expect(!paths.contains("/music/c.mp3"))
        #expect(!paths.contains("/music/d.mp3"))
    }

    @Test("getSongsNeedingLyrics(includePlain: true) also returns plain-lyrics tracks")
    func getSongsNeedingLyricsIncludePlain() async throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let noLyrics = makeTrack(path: "/music/a.mp3", lyrics: nil)
        let plainLyrics = makeTrack(path: "/music/b.mp3", lyrics: "Hello world", lyricType: .plain)
        let syncedLyrics = makeTrack(path: "/music/c.mp3", lyrics: "[00:01.00] Hi", lyricType: .synced)

        try await db.insertOrUpdateSongs([noLyrics, plainLyrics, syncedLyrics])

        let needing = try await db.getSongsNeedingLyrics(includePlain: true)
        let paths = needing.map(\.fileTrackPath)
        #expect(paths.contains("/music/a.mp3"))
        #expect(paths.contains("/music/b.mp3"))
        #expect(!paths.contains("/music/c.mp3"))
    }

    @Test("getSongsNeedingLyrics returns empty when all tracks have synced lyrics")
    func getSongsNeedingLyricsAllSynced() async throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let synced = makeTrack(path: "/music/a.mp3", lyrics: "[00:01.00] Hi", lyricType: .synced)
        try await db.insertOrUpdateSong(synced)

        let needing = try await db.getSongsNeedingLyrics()
        #expect(needing.isEmpty)
    }

    @Test("getSongsNeedingLyrics excludes notFound/noLyricsAvailable tracks by default")
    func getSongsNeedingLyricsExcludesUnresolvedByDefault() async throws {
        // Regression test: notFound/noLyricsAvailable must not be re-queried on every
        // fetch run the way a never-attempted (nil) track is.
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let neverAttempted = makeTrack(path: "/music/a.mp3", lyrics: nil)
        let notFound = makeTrack(path: "/music/b.mp3", lyrics: nil, lyricType: .notFound)
        let noLyricsAvailable = makeTrack(path: "/music/c.mp3", lyrics: nil, lyricType: .noLyricsAvailable)

        try await db.insertOrUpdateSongs([neverAttempted, notFound, noLyricsAvailable])

        let needing = try await db.getSongsNeedingLyrics()
        let paths = needing.map(\.fileTrackPath)
        #expect(paths.contains("/music/a.mp3"))
        #expect(!paths.contains("/music/b.mp3"))
        #expect(!paths.contains("/music/c.mp3"))
    }

    @Test("getSongsNeedingLyrics(includeUnresolved: true) also returns notFound/noLyricsAvailable tracks")
    func getSongsNeedingLyricsIncludeUnresolved() async throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let neverAttempted = makeTrack(path: "/music/a.mp3", lyrics: nil)
        let notFound = makeTrack(path: "/music/b.mp3", lyrics: nil, lyricType: .notFound)
        let noLyricsAvailable = makeTrack(path: "/music/c.mp3", lyrics: nil, lyricType: .noLyricsAvailable)
        let synced = makeTrack(path: "/music/d.mp3", lyrics: "[00:01.00] Hi", lyricType: .synced)

        try await db.insertOrUpdateSongs([neverAttempted, notFound, noLyricsAvailable, synced])

        let needing = try await db.getSongsNeedingLyrics(includeUnresolved: true)
        let paths = needing.map(\.fileTrackPath)
        #expect(paths.contains("/music/a.mp3"))
        #expect(paths.contains("/music/b.mp3"))
        #expect(paths.contains("/music/c.mp3"))
        #expect(!paths.contains("/music/d.mp3"))
    }

    @Test("getSongsNeedingLyrics(includePlain: true, includeUnresolved: true) combines both")
    func getSongsNeedingLyricsCombinedFlags() async throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plain = makeTrack(path: "/music/a.mp3", lyrics: "Hello", lyricType: .plain)
        let notFound = makeTrack(path: "/music/b.mp3", lyrics: nil, lyricType: .notFound)
        let synced = makeTrack(path: "/music/c.mp3", lyrics: "[00:01.00] Hi", lyricType: .synced)

        try await db.insertOrUpdateSongs([plain, notFound, synced])

        let needing = try await db.getSongsNeedingLyrics(includePlain: true, includeUnresolved: true)
        let paths = needing.map(\.fileTrackPath)
        #expect(paths.contains("/music/a.mp3"))
        #expect(paths.contains("/music/b.mp3"))
        #expect(!paths.contains("/music/c.mp3"))
    }

    // MARK: Music Details

    @Test("getMusicDetails categorizes notFound/noLyricsAvailable separately from missing")
    func getMusicDetailsCategorizesNewStates() async throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await db.insertOrUpdateSongs([
            makeTrack(path: "/music/missing.mp3", lyrics: nil),
            makeTrack(path: "/music/notfound.mp3", lyrics: nil, lyricType: .notFound),
            makeTrack(path: "/music/nolyrics.mp3", lyrics: nil, lyricType: .noLyricsAvailable),
            makeTrack(path: "/music/synced.mp3", lyrics: "[00:01.00] Hi", lyricType: .synced),
            makeTrack(path: "/music/plain.mp3", lyrics: "Hi", lyricType: .plain),
            makeTrack(path: "/music/instrumental.mp3", lyrics: nil, lyricType: .instrumental),
        ])

        let details = try await db.getMusicDetails()
        #expect(details?.songs == 6)
        #expect(details?.missing == 1)
        #expect(details?.notFound == 1)
        #expect(details?.noLyricsAvailable == 1)
        #expect(details?.sync == 1)
        #expect(details?.plain == 1)
        #expect(details?.instrumental == 1)
        // "Lyrics" counts only actual usable content (synced/plain/instrumental),
        // not notFound/noLyricsAvailable — those have no content, just a resolved status.
        #expect(details?.lyrics == 3)
    }

    // MARK: Search

    @Test("searchLyrics returns tracks matching lyric content")
    func searchLyricsMatch() async throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let matching = makeTrack(path: "/music/a.mp3", lyrics: "Is this the real life?")
        let nonMatching = makeTrack(path: "/music/b.mp3", lyrics: "Some other lyrics")
        try await db.insertOrUpdateSongs([matching, nonMatching])

        let results = try await db.searchLyrics(query: "real life")
        #expect(results.count == 1)
        #expect(results.first?.fileTrackPath == "/music/a.mp3")
    }

    @Test("searchLyrics returns empty when no match")
    func searchLyricsNoMatch() async throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await db.insertOrUpdateSong(makeTrack(path: "/music/a.mp3", lyrics: "Some lyrics"))

        let results = try await db.searchLyrics(query: "xyz not found")
        #expect(results.isEmpty)
    }

    @Test("searchLyrics is case-insensitive via SQL LIKE")
    func searchLyricsCaseSensitivity() async throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await db.insertOrUpdateSong(makeTrack(path: "/music/a.mp3", lyrics: "Hello World"))

        // SQLite LIKE is case-insensitive for ASCII
        let results = try await db.searchLyrics(query: "hello world")
        #expect(results.count == 1)
    }

    // MARK: Paths and Dates

    @Test("getAllPathsAndDates returns path to date mapping")
    func getAllPathsAndDates() async throws {
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
        try await db.insertOrUpdateSong(track)

        let pathsAndDates = try await db.getAllPathsAndDates()
        #expect(pathsAndDates["/music/song.mp3"] != nil)
    }

    @Test("getAllPathsAndDates returns empty for empty database")
    func getAllPathsAndDatesEmpty() async throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = try await db.getAllPathsAndDates()
        #expect(result.isEmpty)
    }

    // MARK: Track optional fields

    @Test("Track stores optional trackNumber")
    func trackOptionalTrackNumber() async throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let withNumber = makeTrack(path: "/music/a.mp3", trackNumber: 5)
        let withoutNumber = makeTrack(path: "/music/b.mp3", trackNumber: nil)
        try await db.insertOrUpdateSongs([withNumber, withoutNumber])

        let a = try await db.getSongByPath("/music/a.mp3")
        let b = try await db.getSongByPath("/music/b.mp3")
        #expect(a?.trackNumber == 5)
        #expect(b?.trackNumber == nil)
    }

    // MARK: getSongByID

    @Test("getSongByID returns the matching record")
    func getSongByIDReturnsRecord() async throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await db.insertOrUpdateSong(makeTrack(path: "/music/a.mp3", title: "Song A"))
        let (records, _) = try await db.getSongsPaged(offset: 0, limit: 10, query: nil, filter: .all)
        let id = try #require(records.first?.id)

        let record = try await db.getSongByID(id)
        #expect(record?.track.title == "Song A")
    }

    @Test("getSongByID returns nil for unknown id")
    func getSongByIDMissing() async throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let record = try await db.getSongByID(999_999)
        #expect(record == nil)
    }

    // MARK: getSongsPaged

    @Test("getSongsPaged paginates results and reports the total")
    func getSongsPagedPaginates() async throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tracks = (0..<5).map { makeTrack(path: "/music/\($0).mp3", title: "Track \($0)") }
        try await db.insertOrUpdateSongs(tracks)

        let (firstPage, total) = try await db.getSongsPaged(offset: 0, limit: 2, query: nil, filter: .all)
        let (secondPage, _) = try await db.getSongsPaged(offset: 2, limit: 2, query: nil, filter: .all)

        #expect(total == 5)
        #expect(firstPage.count == 2)
        #expect(secondPage.count == 2)
        #expect(Set(firstPage.map(\.id)).isDisjoint(with: Set(secondPage.map(\.id))))
    }

    @Test("getSongsPaged query matches title, artist, or album")
    func getSongsPagedQueryMatches() async throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await db.insertOrUpdateSongs([
            makeTrack(path: "/music/a.mp3", title: "Bohemian Rhapsody", artist: "Queen", album: "A Night at the Opera"),
            makeTrack(path: "/music/b.mp3", title: "Yesterday", artist: "The Beatles", album: "Help!"),
        ])

        let byTitle = try await db.getSongsPaged(offset: 0, limit: 10, query: "Rhapsody", filter: .all)
        let byArtist = try await db.getSongsPaged(offset: 0, limit: 10, query: "beatles", filter: .all)
        let byAlbum = try await db.getSongsPaged(offset: 0, limit: 10, query: "Opera", filter: .all)
        let noMatch = try await db.getSongsPaged(offset: 0, limit: 10, query: "nonexistent", filter: .all)

        #expect(byTitle.records.map(\.track.title) == ["Bohemian Rhapsody"])
        #expect(byArtist.records.map(\.track.title) == ["Yesterday"])
        #expect(byAlbum.records.map(\.track.title) == ["Bohemian Rhapsody"])
        #expect(noMatch.records.isEmpty)
    }

    @Test("getSongsPaged filters by missing or a specific lyric type")
    func getSongsPagedFilters() async throws {
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await db.insertOrUpdateSongs([
            makeTrack(path: "/music/missing.mp3", title: "Missing", lyricType: nil),
            makeTrack(path: "/music/synced.mp3", title: "Synced", lyrics: "[00:00.00] hi", lyricType: .synced),
            makeTrack(path: "/music/plain.mp3", title: "Plain", lyrics: "hi", lyricType: .plain),
        ])

        let missing = try await db.getSongsPaged(offset: 0, limit: 10, query: nil, filter: .missing)
        let synced = try await db.getSongsPaged(offset: 0, limit: 10, query: nil, filter: .type(.synced))
        let all = try await db.getSongsPaged(offset: 0, limit: 10, query: nil, filter: .all)

        #expect(missing.records.map(\.track.title) == ["Missing"])
        #expect(synced.records.map(\.track.title) == ["Synced"])
        #expect(all.total == 3)
    }
}

// MARK: - Nil database guard tests

@Suite("MusicDatabase nil-connection guard tests")
struct MusicDatabaseNilTests {

    @Test("insertOrUpdateSong is a no-op when db is nil")
    func insertOrUpdateSongNilDB() async throws {
        let db = MusicDatabase(nilDatabase: ())
        try await db.insertOrUpdateSong(makeTrack())
        // No throw and no crash — guard returned early
    }

    @Test("insertOrUpdateSongs is a no-op when db is nil")
    func insertOrUpdateSongsNilDB() async throws {
        let db = MusicDatabase(nilDatabase: ())
        try await db.insertOrUpdateSongs([makeTrack(path: "/a.mp3"), makeTrack(path: "/b.mp3")])
    }

    @Test("getAllSongs returns empty array when db is nil")
    func getAllSongsNilDB() async throws {
        let db = MusicDatabase(nilDatabase: ())
        let result = try await db.getAllSongs()
        #expect(result.isEmpty)
    }

    @Test("getSongByPath returns nil when db is nil")
    func getSongByPathNilDB() async throws {
        let db = MusicDatabase(nilDatabase: ())
        let result = try await db.getSongByPath("/music/song.mp3")
        #expect(result == nil)
    }

    @Test("searchLyrics returns empty array when db is nil")
    func searchLyricsNilDB() async throws {
        let db = MusicDatabase(nilDatabase: ())
        let result = try await db.searchLyrics(query: "hello")
        #expect(result.isEmpty)
    }

    @Test("getSongsNeedingLyrics returns empty array when db is nil")
    func getSongsNeedingLyricsNilDB() async throws {
        let db = MusicDatabase(nilDatabase: ())
        let result = try await db.getSongsNeedingLyrics()
        #expect(result.isEmpty)
    }

    @Test("updateSongLyrics is a no-op when db is nil")
    func updateSongLyricsNilDB() async throws {
        let db = MusicDatabase(nilDatabase: ())
        try await db.updateSongLyrics(
            trackPath: "/music/song.mp3",
            lyricsContent: "Hello",
            lyricType: .synced,
            lyricPath: "/music/song.lrc",
            lyricName: "song.lrc"
        )
    }

    @Test("getAllPathsAndDates returns empty dictionary when db is nil")
    func getAllPathsAndDatesNilDB() async throws {
        let db = MusicDatabase(nilDatabase: ())
        let result = try await db.getAllPathsAndDates()
        #expect(result.isEmpty)
    }

    @Test("getSongByID returns nil when db is nil")
    func getSongByIDNilDB() async throws {
        let db = MusicDatabase(nilDatabase: ())
        let result = try await db.getSongByID(1)
        #expect(result == nil)
    }

    @Test("getSongsPaged returns empty results when db is nil")
    func getSongsPagedNilDB() async throws {
        let db = MusicDatabase(nilDatabase: ())
        let (records, total) = try await db.getSongsPaged(offset: 0, limit: 10, query: nil, filter: .all)
        #expect(records.isEmpty)
        #expect(total == 0)
    }
}
