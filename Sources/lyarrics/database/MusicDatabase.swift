import SQLite
import Foundation
import Logging

// These two run once, during `MusicDatabase.init`, and are free (file-scope) functions rather
// than actor instance methods: an actor's non-async init can't call its own isolated instance
// methods synchronously, and a local function nested in init that captures self's properties
// runs into the same restriction (it counts as capturing a not-yet-fully-initialized self,
// which disables the compiler's usual allowance for direct stored-property assignment
// afterward). Declaring the column references locally keeps these fully self-contained.

/// Runs schema migrations using PRAGMA user_version as a version counter.
/// Only called for pre-existing databases.
private func migrateSongsTableIfNeeded(db: Connection) throws {
    let version = (try db.scalar("PRAGMA user_version") as? Int64) ?? 0

    if version < 1 {
        // Migration 1: drop UNIQUE constraint on file_lyric_path.
        // Two audio files with the same base name (e.g. song.flac + song.mp3)
        // legitimately share the same .lrc file, so the constraint was wrong.
        try db.transaction {
            try db.run("""
                CREATE TABLE IF NOT EXISTS songs_v1 (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    file_track_path TEXT NOT NULL UNIQUE,
                    file_track_name TEXT NOT NULL,
                    file_lyric_path TEXT,
                    file_lyric_name TEXT,
                    title TEXT NOT NULL,
                    artist TEXT NOT NULL,
                    album TEXT NOT NULL,
                    duration REAL NOT NULL,
                    track_number INTEGER,
                    lyrics TEXT,
                    instrumental INTEGER NOT NULL,
                    last_modified REAL NOT NULL,
                    is_synced_lyrics INTEGER NOT NULL
                )
                """)
            try db.run("INSERT OR IGNORE INTO songs_v1 SELECT * FROM songs")
            try db.run("DROP TABLE songs")
            try db.run("ALTER TABLE songs_v1 RENAME TO songs")
        }
        try db.run("PRAGMA user_version = 1")
    }

    if version < 2 {
        // Migration 2: replace instrumental (Bool) and is_synced_lyrics (Bool)
        // with a single nullable lyric_type (TEXT) column.
        try db.transaction {
            try db.run("""
                CREATE TABLE IF NOT EXISTS songs_v2 (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    file_track_path TEXT NOT NULL UNIQUE,
                    file_track_name TEXT NOT NULL,
                    file_lyric_path TEXT,
                    file_lyric_name TEXT,
                    title TEXT NOT NULL,
                    artist TEXT NOT NULL,
                    album TEXT NOT NULL,
                    duration REAL NOT NULL,
                    track_number INTEGER,
                    lyrics TEXT,
                    lyric_type TEXT,
                    last_modified REAL NOT NULL
                )
                """)
            try db.run("""
                INSERT INTO songs_v2
                    (id, file_track_path, file_track_name, file_lyric_path, file_lyric_name,
                     title, artist, album, duration, track_number, lyrics, lyric_type, last_modified)
                SELECT id, file_track_path, file_track_name, file_lyric_path, file_lyric_name,
                       title, artist, album, duration, track_number, lyrics,
                       CASE
                           WHEN instrumental = 1 THEN 'instrumental'
                           WHEN is_synced_lyrics = 1 THEN 'synced'
                           WHEN lyrics IS NOT NULL THEN 'plain'
                           ELSE NULL
                       END,
                       last_modified
                FROM songs
                """)
            try db.run("DROP TABLE songs")
            try db.run("ALTER TABLE songs_v2 RENAME TO songs")
        }
        try db.run("PRAGMA user_version = 2")
    }
}

private func createSongsTable(on db: Connection) throws {
    let songs = Table("songs")
    let id = Expression<Int64>("id")
    let fileTrackPath = Expression<String>("file_track_path")
    let fileTrackName = Expression<String>("file_track_name")
    let fileLyricPath = Expression<String?>("file_lyric_path")
    let fileLyricName = Expression<String?>("file_lyric_name")
    let title = Expression<String>("title")
    let artist = Expression<String>("artist")
    let album = Expression<String>("album")
    let duration = Expression<Double>("duration")
    let trackNumber = Expression<Int?>("track_number")
    let lyrics = Expression<String?>("lyrics")
    let lyricType = Expression<String?>("lyric_type")
    let lastModified = Expression<Date>("last_modified")

    // Snapshot whether the songs table exists before we (potentially) create it,
    // so we can distinguish a brand-new database from an existing one.
    let tableExists = (try db.scalar(
        "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='songs'"
    ) as? Int64 ?? 0) > 0

    try db.run(songs.create(ifNotExists: true) { t in
        t.column(id, primaryKey: .autoincrement)
        t.column(fileTrackPath, unique: true)
        t.column(fileTrackName)
        t.column(fileLyricPath)
        t.column(fileLyricName)
        t.column(title)
        t.column(artist)
        t.column(album)
        t.column(duration)
        t.column(trackNumber)
        t.column(lyrics)
        t.column(lyricType)
        t.column(lastModified)
    })

    if tableExists {
        // Existing database: run any pending schema migrations.
        try migrateSongsTableIfNeeded(db: db)
    } else {
        // Brand-new database: schema is already correct, just stamp the version.
        try db.run("PRAGMA user_version = 2")
    }

    // Create indexes for fast searching (after migration, so they land on the live table)
    try db.run(songs.createIndex(title, ifNotExists: true))
    try db.run(songs.createIndex(artist, ifNotExists: true))
    try db.run(songs.createIndex(lyrics, ifNotExists: true))
}

/// Small key/value table for user-configurable settings (currently just the music library path),
/// separate from `songs` since it's schema-less and has nothing to do with per-track migrations.
private func createSettingsTable(on db: Connection) throws {
    let settings = Table("settings")
    let key = Expression<String>("key")
    let value = Expression<String>("value")

    try db.run(settings.create(ifNotExists: true) { t in
        t.column(key, primaryKey: true)
        t.column(value)
    })
}

actor MusicDatabase {
    private let logger = Logger(label: "com.lyarrics.MusicDatabase")
    private var db: Connection?

    // These duplicate the column lists in `createSongsTable`/`createSettingsTable` above — see
    // the comment at the top of this file for why. There is no compile-time link between the
    // two copies (both are just string literals), so a renamed or added column must be updated
    // in both places by hand.
    private let songs = Table("songs")
    private let id = Expression<Int64>("id")
    private let lrclibID = Expression<Int>("lrclib_id")
    private let fileTrackPath = Expression<String>("file_track_path")
    private let fileTrackName = Expression<String>("file_track_name")
    private let fileLyricPath = Expression<String?>("file_lyric_path")
    private let fileLyricName = Expression<String?>("file_lyric_name")
    private let title = Expression<String>("title")
    private let artist = Expression<String>("artist")
    private let album = Expression<String>("album")
    private let duration = Expression<Double>("duration")
    private let trackNumber = Expression<Int?>("track_number")
    private let lyrics = Expression<String?>("lyrics")
    private let lyricType = Expression<String?>("lyric_type")
    private let lastModified = Expression<Date>("last_modified")

    private let settings = Table("settings")
    private let settingKey = Expression<String>("key")
    private let settingValue = Expression<String>("value")

    /// For testing only: creates an instance with no database connection.
    init(nilDatabase _: Void) {}

    init(dbPath: String = ProcessInfo.processInfo.environment["LYARRICS_DB_PATH"] ?? "\(NSHomeDirectory())/.lyarrics/library.db") throws {
        // Create directory if needed
        let dbURL = URL(fileURLWithPath: dbPath)
        try FileManager.default.createDirectory(
            at: dbURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let connection = try Connection(dbPath)
        try createSongsTable(on: connection)
        try createSettingsTable(on: connection)
        db = connection
    }
}

extension MusicDatabase {
    private func rowToTrack(_ row: Row) -> Track {
        Track(
            fileTrackPath: row[fileTrackPath],
            fileTrackName: row[fileTrackName],
            fileLyricPath: row[fileLyricPath],
            fileLyricName: row[fileLyricName],
            title: row[title],
            artist: row[artist],
            album: row[album],
            duration: row[duration],
            trackNumber: row[trackNumber],
            lyrics: row[lyrics],
            lyricType: row[lyricType].flatMap(LyricType.init(rawValue:)),
            lastModified: row[lastModified]
        )
    }

    private func rowToTrackRecord(_ row: Row) -> TrackRecord {
        TrackRecord(id: row[id], track: rowToTrack(row))
    }

    func insertOrUpdateSong(_ song: Track) throws {
        guard let db = db else {
            logger.error("Database connection is nil")
            return
        }
        logger.debug("Inserting/updating song: \(song.title) by \(song.artist)")

        let insert = songs.insert(
            or: .replace,
            fileTrackPath <- song.fileTrackPath,
            fileTrackName <- song.fileTrackName,
            fileLyricPath <- song.fileLyricPath,
            fileLyricName <- song.fileLyricName,
            title <- song.title,
            artist <- song.artist,
            album <- song.album,
            duration <- song.duration,
            trackNumber <- song.trackNumber,
            lyrics <- song.lyrics,
            lyricType <- song.lyricType?.rawValue,
            lastModified <- song.lastModified
        )

        try db.run(insert)
    }

    func searchLyrics(query: String) throws -> [Track] {
        guard let db = db else {
            logger.error("Database connection is nil")
            return []
        }
        logger.info("Searching lyrics for: \(query)")

        let searchQuery = songs.filter(lyrics.like("%\(query)%"))
        return try db.prepare(searchQuery).map(rowToTrack)
    }

    func getSongByPath(_ path: String) throws -> Track? {
        guard let db = db else {
            logger.error("Database connection is nil")
            return nil
        }
        logger.debug("Looking up song by path: \(path)")

        let query = songs.filter(fileTrackPath == path).limit(1)
        return try db.prepare(query).map(rowToTrack).first
    }

    func getSongByID(_ recordID: Int64) throws -> TrackRecord? {
        guard let db = db else {
            logger.error("Database connection is nil")
            return nil
        }
        logger.debug("Looking up song by id: \(recordID)")

        let query = songs.filter(id == recordID).limit(1)
        return try db.prepare(query).map(rowToTrackRecord).first
    }

    /// - Parameters:
    ///   - query: when non-empty, matches against title, artist, or album (case-insensitive substring).
    ///   - filter: narrows to tracks missing lyrics, tracks of a specific `LyricType`, or all tracks.
    /// - Returns: the page of matching records plus the total count of matching rows (for pagination).
    func getSongsPaged(offset: Int, limit: Int, query: String?, filter: LibraryFilter) throws -> (records: [TrackRecord], total: Int) {
        guard let db = db else {
            logger.error("Database connection is nil")
            return ([], 0)
        }

        var filtered = songs
        if let query, !query.isEmpty {
            filtered = filtered.filter(title.like("%\(query)%") || artist.like("%\(query)%") || album.like("%\(query)%"))
        }
        switch filter {
        case .all:
            break
        case .missing:
            filtered = filtered.filter(lyricType == nil)
        case .type(let lyricTypeFilter):
            filtered = filtered.filter(lyricType == lyricTypeFilter.rawValue)
        }

        let total = try db.scalar(filtered.count)
        let paged = filtered.order(artist.asc, title.asc).limit(limit, offset: offset)
        let records = try db.prepare(paged).map(rowToTrackRecord)
        return (records, total)
    }

    /// - Parameters:
    ///   - includePlain: when `true`, also returns tracks that already have plain (unsynced)
    ///     lyrics, so they can be re-fetched in case a synced version is now available.
    ///     Defaults to `false` so a plain-lyrics track isn't re-requested from LRCLIB on every run.
    ///   - includeUnresolved: when `true`, also returns tracks previously confirmed absent from
    ///     LRCLIB (`notFound`) or confirmed to have no lyrics submitted (`noLyricsAvailable`).
    ///     Defaults to `false` for the same reason as `includePlain` — LRCLIB's catalog does grow
    ///     over time, but re-checking every "we already looked, nothing there" track on every run
    ///     would re-run the exact same doomed lookups forever.
    func getSongsNeedingLyrics(includePlain: Bool = false, includeUnresolved: Bool = false) throws -> [Track] {
        guard let db = db else {
            logger.error("Database connection is nil")
            return []
        }
        logger.info("Fetching songs that need lyrics")

        var resolvedTypesToRecheck: [String] = []
        if includePlain {
            resolvedTypesToRecheck.append(LyricType.plain.rawValue)
        }
        if includeUnresolved {
            resolvedTypesToRecheck.append(LyricType.notFound.rawValue)
            resolvedTypesToRecheck.append(LyricType.noLyricsAvailable.rawValue)
        }

        // An empty `IN ()` is invalid SQL, so only add the clause when there's something to recheck.
        let query = resolvedTypesToRecheck.isEmpty
            ? songs.filter(lyricType == nil)
            : songs.filter(lyricType == nil || resolvedTypesToRecheck.contains(lyricType))
        return try db.prepare(query).map(rowToTrack)
    }

    func updateSongLyrics(trackPath: String, lyricsContent: String?, lyricType newLyricType: LyricType?, lyricPath: String?, lyricName: String?) throws {
        guard let db = db else {
            logger.error("Database connection is nil")
            return
        }
        logger.debug("Updating lyrics for: \(trackPath)")

        let song = songs.filter(fileTrackPath == trackPath)
        try db.run(song.update(
            lyrics <- lyricsContent,
            lyricType <- newLyricType?.rawValue,
            fileLyricPath <- lyricPath,
            fileLyricName <- lyricName
        ))
    }

    func getAllPathsAndDates() throws -> [String: Date] {
        guard let db = db else {
            logger.error("Database connection is nil")
            return [:]
        }
        var result: [String: Date] = [:]
        for row in try db.prepare(songs.select(fileTrackPath, lastModified)) {
            result[row[fileTrackPath]] = row[lastModified]
        }
        return result
    }

    func insertOrUpdateSongs(_ tracks: [Track]) throws {
        guard let db = db else {
            logger.error("Database connection is nil")
            return
        }
        // Written out as explicit BEGIN/COMMIT/ROLLBACK rather than `db.transaction { ... }`:
        // that convenience wrapper internally hops through a blocking `DispatchQueue.sync`
        // (for thread-safety across concurrent `Connection` users), and Swift 6's strict
        // concurrency checker flags a closure-within-that-closure capturing the non-Sendable
        // `Connection` as risking a data race — even though this actor already serializes every
        // caller, making that internal hop redundant here. Same atomicity, no closure nesting.
        try db.run("BEGIN TRANSACTION")
        do {
            for song in tracks {
                let insert = songs.insert(
                    or: .replace,
                    fileTrackPath <- song.fileTrackPath,
                    fileTrackName <- song.fileTrackName,
                    fileLyricPath <- song.fileLyricPath,
                    fileLyricName <- song.fileLyricName,
                    title <- song.title,
                    artist <- song.artist,
                    album <- song.album,
                    duration <- song.duration,
                    trackNumber <- song.trackNumber,
                    lyrics <- song.lyrics,
                    lyricType <- song.lyricType?.rawValue,
                    lastModified <- song.lastModified
                )
                try db.run(insert)
            }
            try db.run("COMMIT TRANSACTION")
        } catch {
            try db.run("ROLLBACK TRANSACTION")
            throw error
        }
    }

    func getAllSongs() throws -> [Track] {
        guard let db = db else {
            logger.error("Database connection is nil")
            return []
        }
        logger.info("Fetching all songs")
        return try db.prepare(songs).map(rowToTrack)
    }

    func getMusicDetails() throws -> MusicDetails? {
        guard let db = db else {
            logger.error("Database connection is nil")
            return nil
        }
        logger.info("Getting Music Details")

        var details: MusicDetails = .init(
            songs: 0,
            lyrics: 0,
            plain: 0,
            sync: 0,
            instrumental: 0,
            missing: 0,
            notFound: 0,
            noLyricsAvailable: 0
            )

        for row in try db.prepare(songs) {
            details.songs += 1
            switch row[lyricType].flatMap(LyricType.init(rawValue:)) {
            case .synced:
                details.lyrics += 1
                details.sync += 1
            case .plain:
                details.lyrics += 1
                details.plain += 1
            case .instrumental:
                details.lyrics += 1
                details.instrumental += 1
            case .notFound:
                details.notFound += 1
            case .noLyricsAvailable:
                details.noLyricsAvailable += 1
            case nil:
                details.missing += 1
            }
        }

        return details
    }

    // MARK: - Settings

    func getSetting(_ key: String) throws -> String? {
        guard let db = db else {
            logger.error("Database connection is nil")
            return nil
        }
        let query = settings.filter(settingKey == key).limit(1)
        return try db.prepare(query).map { $0[settingValue] }.first
    }

    func setSetting(_ key: String, value: String) throws {
        guard let db = db else {
            logger.error("Database connection is nil")
            return
        }
        try db.run(settings.insert(or: .replace, settingKey <- key, settingValue <- value))
    }

    static let musicPathSettingKey = "musicPath"

    /// The saved music library path, falling back to `LYARRICS_MUSIC_PATH` (useful for Docker
    /// deployments where the container always mounts the library at a fixed path) when nothing
    /// has been saved yet.
    func getMusicPath() throws -> String {
        try getSetting(Self.musicPathSettingKey) ?? ProcessInfo.processInfo.environment["LYARRICS_MUSIC_PATH"] ?? ""
    }

    func setMusicPath(_ path: String) throws {
        try setSetting(Self.musicPathSettingKey, value: path)
    }
}
