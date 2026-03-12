import SQLite
import Foundation
import Logging

class MusicDatabase {
    private let logger = Logger(label: "com.lyarrics.MusicDatabase")
    private var db: Connection?

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

    /// For testing only: creates an instance with no database connection.
    init(nilDatabase _: Void) {}

    init(dbPath: String = ProcessInfo.processInfo.environment["LYARRICS_DB_PATH"] ?? "\(NSHomeDirectory())/.lyarrics/library.db") throws {
        // Create directory if needed
        let dbURL = URL(fileURLWithPath: dbPath)
        try FileManager.default.createDirectory(
            at: dbURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        logger.info("Opening database at \(dbPath)")
        db = try Connection(dbPath)
        try createTable()
    }

    private func createTable() throws {
        guard let db = db else { return }

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
            try migrateIfNeeded(db: db)
        } else {
            // Brand-new database: schema is already correct, just stamp the version.
            try db.run("PRAGMA user_version = 2")
        }

        // Create indexes for fast searching (after migration, so they land on the live table)
        try db.run(songs.createIndex(title, ifNotExists: true))
        try db.run(songs.createIndex(artist, ifNotExists: true))
        try db.run(songs.createIndex(lyrics, ifNotExists: true))
    }

    /// Runs schema migrations using PRAGMA user_version as a version counter.
    /// Only called for pre-existing databases.
    private func migrateIfNeeded(db: Connection) throws {
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
}

extension MusicDatabase {
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
        var results: [Track] = []

        for row in try db.prepare(searchQuery) {
            results.append(Track(
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
            ))
        }

        return results
    }

    func getSongByPath(_ path: String) throws -> Track? {
        guard let db = db else {
            logger.error("Database connection is nil")
            return nil
        }
        logger.debug("Looking up song by path: \(path)")

        let query = songs.filter(fileTrackPath == path).limit(1)

        for row in try db.prepare(query) {
            return Track(
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

        return nil
    }

    func getSongsNeedingLyrics() throws -> [Track] {
        guard let db = db else {
            logger.error("Database connection is nil")
            return []
        }
        logger.info("Fetching songs that need lyrics")

        let query = songs.filter(lyricType == nil || lyricType == LyricType.plain.rawValue)
        var results: [Track] = []

        for row in try db.prepare(query) {
            results.append(Track(
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
            ))
        }

        return results
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
        try db.transaction {
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
        }
    }

    func getAllSongs() throws -> [Track] {
        guard let db = db else {
            logger.error("Database connection is nil")
            return []
        }
        logger.info("Fetching all songs")

        var results: [Track] = []

        for row in try db.prepare(songs) {
            results.append(Track(
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
            ))
        }

        return results
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
            missing: 0
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
            case nil:
                details.missing += 1
            }
        }

        return details
    }
}
