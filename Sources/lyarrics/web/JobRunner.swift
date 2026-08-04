import Foundation
import Hummingbird
import LRCLib
import Logging

/// Coordinates background scan/fetch runs triggered from the web UI, reusing the same
/// `LibraryScanner`/`Fetch` code paths the CLI uses. Only one job runs at a time — `start*`
/// returns `false` immediately if a job is already in flight, rather than queuing a second one.
actor JobRunner {
    enum Kind: String, Codable, Sendable {
        case scan
        case fetch
    }

    enum State: String, Codable, Sendable {
        case idle
        case running
        case succeeded
        case failed
    }

    struct Snapshot: Codable, Sendable {
        var state: State = .idle
        var kind: Kind?
        var processed: Int = 0
        var total: Int = 0
        var message: String?
        var startedAt: Date?
        var finishedAt: Date?
    }

    private var snapshot = Snapshot()
    private var isRunning = false

    func status() -> Snapshot { snapshot }

    @discardableResult
    func startScan(path: String, database: MusicDatabase) -> Bool {
        guard !isRunning else { return false }
        isRunning = true
        snapshot = Snapshot(state: .running, kind: .scan, processed: 0, total: 0, startedAt: Date())

        // No `await` on the `self.finish`/`self.fail` calls below: a `Task` spawned from within
        // an actor-isolated method inherits that actor's isolation, so these are already running
        // on JobRunner's executor — the compiler flags an explicit `await` here as a no-op. This
        // isn't obvious at a glance, so don't "fix" it by adding `await` back in.
        Task {
            let scanner = LibraryScanner(musicDirectory: URL(fileURLWithPath: path), database: database)
            do {
                let failures = try await scanner.scanLibrary { completed, total in
                    await self.updateProgress(processed: completed, total: total)
                }
                let message = failures.isEmpty
                    ? "Scan complete."
                    : "Scan complete. \(failures.count) file(s) failed to read — see logs for details."
                self.finish(message: message)
            } catch {
                self.fail(error: error)
            }
        }
        return true
    }

    /// - Parameters:
    ///   - options: a configured `Fetch` value (concurrency, delay, limit, etc.) — the same type
    ///     and validation the CLI `fetch` subcommand uses. Start from `Fetch.makeDefault()`
    ///     rather than `Fetch()` (see its doc comment for why). Its `dryRun` is ignored;
    ///     web-triggered fetches always write.
    ///   - client: defaults to a real `LRCLibClient()`; overridable so tests can inject a mock
    ///     without hitting the network.
    @discardableResult
    func startFetch(options: Fetch, database: MusicDatabase, client: LRCLibClient = LRCLibClient()) -> Bool {
        guard !isRunning else { return false }
        isRunning = true
        snapshot = Snapshot(state: .running, kind: .fetch, processed: 0, total: 0, startedAt: Date())

        // Same inherited-isolation note as in startScan above applies to the non-awaited
        // self.finish/self.fail calls below.
        Task {
            var fetchCommand = options
            fetchCommand.dryRun = false
            do {
                try fetchCommand.validate()

                var songsNeedingLyrics = try await database.getSongsNeedingLyrics(
                    includePlain: fetchCommand.upgradePlain,
                    includeUnresolved: fetchCommand.recheckUnresolved
                )
                if let limit = fetchCommand.limit {
                    songsNeedingLyrics = Array(songsNeedingLyrics.prefix(limit))
                }
                self.updateProgress(processed: 0, total: songsNeedingLyrics.count)

                guard !songsNeedingLyrics.isEmpty else {
                    self.finish(message: "No songs need lyrics. Nothing to do.")
                    return
                }

                let rateLimiter = RateLimiter(milliseconds: fetchCommand.delay)
                let logger = Logger(label: "com.lyarrics.JobRunner.fetch")
                let (fetched, failed) = try await fetchCommand.process(
                    songsNeedingLyrics: songsNeedingLyrics,
                    database: database,
                    client: client,
                    rateLimiter: rateLimiter,
                    logger: logger
                ) { processed, total, _, _ in
                    await self.updateProgress(processed: processed, total: total)
                }
                self.finish(message: "Fetch complete. Fetched: \(fetched), Failed: \(failed).")
            } catch {
                self.fail(error: error)
            }
        }
        return true
    }

    private func updateProgress(processed: Int, total: Int) {
        snapshot.processed = processed
        snapshot.total = total
    }

    private func finish(message: String) {
        snapshot.state = .succeeded
        snapshot.message = message
        snapshot.finishedAt = Date()
        isRunning = false
    }

    private func fail(error: Error) {
        snapshot.state = .failed
        snapshot.message = "\(error)"
        snapshot.finishedAt = Date()
        isRunning = false
    }
}

/// Lets a route handler `return jobRunner.status()` directly and have Hummingbird JSON-encode it.
extension JobRunner.Snapshot: ResponseEncodable {}
