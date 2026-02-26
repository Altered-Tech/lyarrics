import ArgumentParser
import LRCLib
import Foundation
import Logging

// MARK: - Rate Limiter

/// Throttles requests by spacing them at least `delay` ms apart.
/// Uses slot-claiming so concurrent callers each get a unique future slot,
/// preventing bursts even when multiple tasks call throttle() simultaneously.
private actor RateLimiter {
    private let delaySeconds: Double
    private var lastRequest: Date

    init(milliseconds: Int) {
        self.delaySeconds = Double(milliseconds) / 1000.0
        // Start far enough in the past so the first request fires immediately
        self.lastRequest = Date(timeIntervalSinceNow: -(Double(milliseconds) / 1000.0 + 1.0))
    }

    func throttle() async throws {
        let nextAllowed = lastRequest.addingTimeInterval(delaySeconds)
        let now = Date()
        // Claim this slot before suspending so no two tasks share the same window
        lastRequest = nextAllowed > now ? nextAllowed : now
        let sleepSeconds = nextAllowed.timeIntervalSince(now)
        if sleepSeconds > 0 {
            try await Task.sleep(nanoseconds: UInt64(sleepSeconds * 1_000_000_000))
        }
    }
}

// MARK: - Fetch Outcome

private enum FetchOutcome: Sendable {
    case synced(content: String, lrcURL: URL, isInstrumental: Bool)
    case plain(content: String, lrcURL: URL, isInstrumental: Bool)
    case instrumental
    case noLyrics
    case notFound
    case apiError(statusCode: Int)
    case decodingError(description: String)
    case unknownError(description: String)
}

// MARK: - Fetch Command

struct Fetch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Fetch lyrics from the command line"
    )

    private static let logger = Logger(label: "com.lyarrics.Fetch")

    @Argument(help: "The path to scan")
    var path: String

    @Flag(name: .long, help: "Show what would be fetched without writing files or updating the database")
    var dryRun: Bool = false

    @Option(name: .long, help: "Maximum number of retries for transient errors")
    var maxRetries: Int = 3

    @Option(name: .long, help: "Delay in milliseconds between API requests")
    var delay: Int = 500

    @Option(name: .long, help: "Number of concurrent API requests")
    var concurrency: Int = 5

    @Flag(name: .long, help: "Rescan library for any changes before fetching lyrics")
    var scan: Bool = false

    func run() async throws {
        let logger = Self.logger

        let database = try MusicDatabase()
        let musicDirectory = URL(fileURLWithPath: path)

        if scan {
            let scanner = LibraryScanner(musicDirectory: musicDirectory, database: database)
            logger.info("Scanning library at \(path)")
            try await scanner.scanLibrary()
            logger.info("Scan complete")
        }

        let songsNeedingLyrics = try database.getSongsNeedingLyrics()
        logger.info("Found \(songsNeedingLyrics.count) songs needing lyrics")

        if dryRun {
            logger.info("Dry run enabled, no files will be written or database updated")
        }

        let lrc = LRCLibClient()
        let rateLimiter = RateLimiter(milliseconds: delay)
        var fetched = 0
        var failed = 0

        try await withThrowingTaskGroup(of: (Track, FetchOutcome).self) { group in
            var trackIterator = songsNeedingLyrics.makeIterator()

            // Seed the pool with up to `concurrency` initial tasks
            for _ in 0..<min(concurrency, songsNeedingLyrics.count) {
                guard let track = trackIterator.next() else { break }
                group.addTask {
                    await self.fetchTrackOutcome(track: track, client: lrc, rateLimiter: rateLimiter, logger: logger)
                }
            }

            // Process results serially (safe for DB writes) and keep the pool full
            for try await (track, outcome) in group {
                switch outcome {
                case .synced(let content, let lrcURL, let isInstrumental):
                    if !dryRun {
                        try content.write(to: lrcURL, atomically: true, encoding: .utf8)
                        try database.updateSongLyrics(
                            trackPath: track.fileTrackPath,
                            lyricsContent: content,
                            isSynced: true,
                            isInstrumental: isInstrumental,
                            lyricPath: lrcURL.path,
                            lyricName: lrcURL.lastPathComponent
                        )
                    }
                    logger.info("[syncd] \(track.artist) - \(track.title) -> \(lrcURL.lastPathComponent)")
                    fetched += 1

                case .plain(let content, let lrcURL, let isInstrumental):
                    if !dryRun {
                        try content.write(to: lrcURL, atomically: true, encoding: .utf8)
                        try database.updateSongLyrics(
                            trackPath: track.fileTrackPath,
                            lyricsContent: content,
                            isSynced: false,
                            isInstrumental: isInstrumental,
                            lyricPath: lrcURL.path,
                            lyricName: lrcURL.lastPathComponent
                        )
                    }
                    logger.info("[plain] \(track.artist) - \(track.title) -> \(lrcURL.lastPathComponent)")
                    fetched += 1

                case .instrumental:
                    if !dryRun {
                        try database.updateSongLyrics(
                            trackPath: track.fileTrackPath,
                            lyricsContent: nil,
                            isSynced: false,
                            isInstrumental: true,
                            lyricPath: nil,
                            lyricName: nil
                        )
                    }
                    logger.info("[instrumental] \(track.artist) - \(track.title)")
                    fetched += 1

                case .noLyrics:
                    logger.warning("[none] \(track.artist) - \(track.title)")
                    fetched += 1

                case .notFound:
                    logger.warning("Not found on LRCLIB: \(track.artist) - \(track.title)")
                    failed += 1

                case .apiError(let code):
                    logger.error("LRCLIB error \(code) for: \(track.artist) - \(track.title)")
                    failed += 1

                case .decodingError(let description):
                    logger.error("Decoding error for \(track.artist) - \(track.title): \(description)")

                case .unknownError(let description):
                    logger.error("Unknown error for \(track.artist) - \(track.title): \(description)")
                }

                // Replenish the pool as each result comes in
                if let next = trackIterator.next() {
                    group.addTask {
                        await self.fetchTrackOutcome(track: next, client: lrc, rateLimiter: rateLimiter, logger: logger)
                    }
                }
            }
        }

        logger.info("Fetch complete. Fetched: \(fetched), Failed: \(failed)")
    }

    // MARK: - Helpers

    private func fetchTrackOutcome(track: Track, client: LRCLibClient, rateLimiter: RateLimiter, logger: Logger) async -> (Track, FetchOutcome) {
        let song = Song(
            track: LRCLib.Track(track.title),
            artist: Artist(track.artist),
            album: Album(track.album),
            duration: Duration(Int(track.duration))
        )

        do {
            try await rateLimiter.throttle()
            logger.debug("Fetching lyrics for: \(track.artist) - \(track.title)")
            let record = try await fetchWithRetry(client: client, song: song, logger: logger)

            let trackURL = URL(fileURLWithPath: track.fileTrackPath)
            let lrcURL = trackURL.deletingPathExtension().appendingPathExtension("lrc")

            if let syncedLyrics = record.syncedLyrics {
                return (track, .synced(content: syncedLyrics, lrcURL: lrcURL, isInstrumental: record.instrumental))
            } else if let plainLyrics = record.plainLyrics {
                return (track, .plain(content: plainLyrics, lrcURL: lrcURL, isInstrumental: record.instrumental))
            } else if record.instrumental {
                return (track, .instrumental)
            } else {
                return (track, .noLyrics)
            }
        } catch let error as LRCError {
            switch error {
            case .notFound:
                return (track, .notFound)
            case .undocumented(let code, _):
                return (track, .apiError(statusCode: code))
            case .decodingError(let underlying):
                let description = underlying.map { String(describing: $0) } ?? "Unknown decoding error"
                return (track, .decodingError(description: description))
            }
        } catch {
            return (track, .unknownError(description: error.localizedDescription))
        }
    }

    private func fetchWithRetry(client: LRCLibClient, song: Song, logger: Logger) async throws -> Record {
        var lastError: Error?
        for attempt in 1...maxRetries {
            do {
                return try await client.getLyrics(song: song)
            } catch let error where !(error is LRCError) {
                lastError = error
                let backoff = UInt64(attempt) * UInt64(delay) * 1_000_000
                logger.warning("Transient error (attempt \(attempt)/\(maxRetries)), retrying in \(attempt * delay)ms: \(error.localizedDescription)")
                try await Task.sleep(nanoseconds: backoff)
            }
        }
        throw lastError!
    }
}
