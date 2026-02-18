import ArgumentParser
import LRCLib
import Foundation
import os

struct Fetch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Fetch lyrics from the command line"
    )

    private static let logger = Logger(subsystem: "com.lyarrics", category: "Fetch")

    @Argument(help: "The path to scan")
    var path: String

    @Flag(name: .long, help: "Show what would be fetched without writing files or updating the database")
    var dryRun: Bool = false

    @Option(name: .long, help: "Maximum number of retries for transient errors")
    var maxRetries: Int = 3

    @Option(name: .long, help: "Delay in milliseconds between API requests")
    var delay: Int = 500

    @Flag(name: .long, help: "Rescan library for any changes before fetching lyrics")
    var scan: Bool = false

    func run() async throws {
        let logger = Self.logger

        let database = try MusicDatabase()
        let musicDirectory = URL(fileURLWithPath: path)

        if scan {
            let scanner = LibraryScanner(musicDirectory: musicDirectory, database: database)

            logger.info("Scanning library at \(path, privacy: .public)")
            try await scanner.scanLibrary()
            logger.info("Scan complete")
        }

        let songsNeedingLyrics = try database.getSongsNeedingLyrics()
        logger.info("Found \(songsNeedingLyrics.count, privacy: .public) songs needing lyrics")

        if dryRun {
            logger.info("Dry run enabled, no files will be written or database updated")
        }

        let lrc = LRCLibClient()
        var fetched = 0
        var failed = 0

        for track in songsNeedingLyrics {
            logger.debug("Fetching lyrics for: \(track.artist, privacy: .public) - \(track.title, privacy: .public)")

            let song = Song(
                track: LRCLib.Track(track.title),
                artist: Artist(track.artist),
                album: Album(track.album),
                duration: Duration(Int(track.duration))
            )

            try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)

            do {
                let record: Record = try await fetchWithRetry(client: lrc, song: song, logger: logger)

                if let syncedLyricsContent = record.syncedLyrics {
                    let trackURL = URL(fileURLWithPath: track.fileTrackPath)
                    let lrcURL = trackURL.deletingPathExtension().appendingPathExtension("lrc")

                    if !dryRun {
                        try syncedLyricsContent.write(to: lrcURL, atomically: true, encoding: .utf8)
                        logger.info("Wrote synced lyrics to \(lrcURL.path, privacy: .public)")

                        try database.updateSongLyrics(
                            trackPath: track.fileTrackPath,
                            lyricsContent: record.syncedLyrics,
                            isSynced: true,
                            isInstrumental: record.instrumental,
                            lyricPath: lrcURL.path,
                            lyricName: lrcURL.lastPathComponent
                        )
                    }

                    logger.info("[syncd] \(track.artist, privacy: .public) - \(track.title, privacy: .public) -> \(lrcURL.lastPathComponent, privacy: .public)")

                } else if let plainLyrics = record.plainLyrics  {
                    let trackURL = URL(fileURLWithPath: track.fileTrackPath)
                    let lrcURL = trackURL.deletingPathExtension().appendingPathExtension("lrc")

                    if !dryRun {
                        try plainLyrics.write(to: lrcURL, atomically: true, encoding: .utf8)
                        logger.info("Wrote plain lyrics to \(lrcURL.path, privacy: .public)")

                        try database.updateSongLyrics(
                            trackPath: track.fileTrackPath,
                            lyricsContent: plainLyrics,
                            isSynced: false,
                            isInstrumental: record.instrumental,
                            lyricPath: lrcURL.path,
                            lyricName: lrcURL.lastPathComponent
                        )

                    }
                        logger.info("[plain] \(track.artist, privacy: .public) - \(track.title, privacy: .public) -> \(lrcURL.lastPathComponent, privacy: .public)")
                } else if record.instrumental == true {
                    if !dryRun {
                        try database.updateSongLyrics(
                            trackPath: track.fileTrackPath,
                            lyricsContent: nil,
                            isSynced: false,
                            isInstrumental: record.instrumental,
                            lyricPath: nil,
                            lyricName: nil
                        )
                    }

                    logger.info("[instrumental] \(track.artist, privacy: .public) - \(track.title, privacy: .public)")
                } else {
                    logger.warning("[None] \(track.artist, privacy: .public) - \(track.title, privacy: .public)")
                }

                fetched += 1
            } catch LRCError.notFound {
                logger.warning("Not found on LRCLIB: \(track.artist, privacy: .public) - \(track.title, privacy: .public)")
                failed += 1
            } catch LRCError.undocumented(let code, _) {
                logger.error("LRCLIB error \(code, privacy: .public) for: \(track.artist, privacy: .public) - \(track.title, privacy: .public)")
                failed += 1
            } catch LRCError.decodingError(let error) {
                logger.error("Decoding Error: \(error, privacy: .public) for \(track.artist, privacy: .public) - \(track.title, privacy: .public)") 
            }catch {
                logger.error("Unknown Error: \(error, privacy: .public) for \(track.artist, privacy: .public) - \(track.title, privacy: .public)")
            }
        }

        logger.info("Fetch complete. Fetched: \(fetched, privacy: .public), Failed: \(failed, privacy: .public)")
    }

    private func fetchWithRetry(client: LRCLibClient, song: Song, logger: Logger) async throws -> Record {
        var lastError: Error?
        for attempt in 1...maxRetries {
            do {
                return try await client.getLyrics(song: song)
            } catch let error where !(error is LRCError) {
                lastError = error
                let backoff = UInt64(attempt) * UInt64(delay) * 1_000_000
                logger.warning("Transient error (attempt \(attempt, privacy: .public)/\(maxRetries, privacy: .public)), retrying in \(attempt * delay, privacy: .public)ms: \(error.localizedDescription, privacy: .public)")
                try await Task.sleep(nanoseconds: backoff)
            }
        }
        throw lastError!
    }
}
