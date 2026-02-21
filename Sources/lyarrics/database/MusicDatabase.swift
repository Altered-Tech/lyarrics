import SQLite
import Foundation
import os

class MusicDatabase {
    private let logger = Logger(subsystem: "com.lyarrics", category: "MusicDatabase")
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
    private let isSyncedLyrics = Expression<Bool>("is_synced_lyrics")
    private let instrumental = Expression<Bool>("instrumental")
    private let lastModified = Expression<Date>("last_modified")

    init(dbPath: String = "\(NSHomeDirectory())/.lyarrics/library.db") throws {
        // Create directory if needed
        let dbURL = URL(fileURLWithPath: dbPath)
        try FileManager.default.createDirectory(
            at: dbURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        logger.info("Opening database at \(dbPath, privacy: .public)")
        db = try Connection(dbPath)
        try createTable()
    }

    private func createTable() throws {
        try db?.run(songs.create(ifNotExists: true) { t in
            t.column(id, primaryKey: .autoincrement)
            t.column(fileTrackPath, unique: true)
            t.column(fileTrackName)
            t.column(fileLyricPath, unique: true)
            t.column(fileLyricName)
            t.column(title)
            t.column(artist)
            t.column(album)
            t.column(duration)
            t.column(trackNumber)
            t.column(lyrics)
            t.column(instrumental)
            t.column(lastModified)
            t.column(isSyncedLyrics)
        })
        
        // Create indexes for fast searching
        try db?.run(songs.createIndex(title, ifNotExists: true))
        try db?.run(songs.createIndex(artist, ifNotExists: true))
        try db?.run(songs.createIndex(lyrics, ifNotExists: true))
    }
}

extension MusicDatabase {
    func insertOrUpdateSong(_ song: Track) throws {
        guard let db = db else {
            logger.error("Database connection is nil")
            return
        }
        logger.debug("Inserting/updating song: \(song.title, privacy: .public) by \(song.artist, privacy: .public)")
        
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
            instrumental <- song.instrumental,
            isSyncedLyrics <- song.isSyncedLyrics,
            lastModified <- song.lastModified
        )
        
        try db.run(insert)
    }
    
    func searchLyrics(query: String) throws -> [Track] {
        guard let db = db else {
            logger.error("Database connection is nil")
            return []
        }
        logger.info("Searching lyrics for: \(query, privacy: .public)")
        
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
                instrumental: row[instrumental],
                isSyncedLyrics: row[isSyncedLyrics],
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
        logger.debug("Looking up song by path: \(path, privacy: .public)")
        
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
                instrumental: row[instrumental],
                isSyncedLyrics: row[isSyncedLyrics],
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

        let query = songs.filter(lyrics == nil || isSyncedLyrics == false)
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
                instrumental: row[instrumental],
                isSyncedLyrics: row[isSyncedLyrics],
                lastModified: row[lastModified]
            ))
        }

        return results
    }

    func updateSongLyrics(trackPath: String, lyricsContent: String?, isSynced: Bool, isInstrumental: Bool, lyricPath: String?, lyricName: String?) throws {
        guard let db = db else {
            logger.error("Database connection is nil")
            return
        }
        logger.debug("Updating lyrics for: \(trackPath, privacy: .public)")

        let song = songs.filter(fileTrackPath == trackPath)
        try db.run(song.update(
            lyrics <- lyricsContent,
            isSyncedLyrics <- isSynced,
            instrumental <- isInstrumental,
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
                    instrumental <- song.instrumental,
                    isSyncedLyrics <- song.isSyncedLyrics,
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
                instrumental: row[instrumental],
                isSyncedLyrics: row[isSyncedLyrics],
                lastModified: row[lastModified]
            ))
        }
        
        return results
    }
}