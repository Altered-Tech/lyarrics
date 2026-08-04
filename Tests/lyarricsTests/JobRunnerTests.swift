import Testing
import Foundation
import OpenAPIRuntime
@testable import LRCLib
@testable import lyarrics

// MARK: - Helpers

private func makeTestDatabase() throws -> (MusicDatabase, URL) {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("JobRunnerTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let db = try MusicDatabase(dbPath: tempDir.appendingPathComponent("test.db").path)
    return (db, tempDir)
}

// `Swift.Duration` is qualified throughout this file because `@testable import LRCLib` (needed
// for the mock API client below) also defines a type named `Duration`, which would otherwise
// shadow the concurrency one meant here. Track construction uses `makeLyarricsTrack` from
// FetchTestHelpers.swift instead of building a `Track` locally, for the same reason — `lyarrics`
// is both the module name and the `@main` command type name, so `lyarrics.Track` doesn't resolve
// the way it looks like it should either.

/// Populates `musicDir` with `count` empty, non-audio files that still carry a recognized music
/// extension — enough for `LibraryScanner` to enumerate and attempt (and fail) to read via
/// ffprobe, so a scan over them takes measurable wall-clock time without depending on real audio
/// fixtures. Used to make the "second start is rejected while running" test deterministic: the
/// job needs to still be running when the second `startScan` call lands.
private func makeSlowScanDirectory(fileCount: Int = 400) throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("JobRunnerTests-slow-scan-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    for i in 0..<fileCount {
        FileManager.default.createFile(atPath: tempDir.appendingPathComponent("track\(i).mp3").path, contents: nil)
    }
    return tempDir
}

/// A `Fetch` with every ArgumentParser-wrapped property explicitly set — reading one that was
/// only left at its declared default (rather than assigned) crashes at runtime, so every call
/// site that builds a `Fetch()` outside of CLI parsing must set all of them explicitly. Use
/// `Fetch.makeDefault()` as the base rather than repeating that ritual here.
private func makeFetchOptions(delay: Int = 0, concurrency: Int = 1, limit: Int? = nil) -> Fetch {
    var fetch = Fetch.makeDefault()
    fetch.maxRetries = 1
    fetch.delay = delay
    fetch.concurrency = concurrency
    fetch.limit = limit
    return fetch
}

/// Returns one `getLyrics` response after an artificial delay — long enough that a fetch job
/// processing even a single track is still `.running` by the time a second `startFetch` call
/// lands right after the first, without depending on real network timing.
private final class SlowMockAPIClient: APIProtocol, @unchecked Sendable {
    private let delay: Swift.Duration

    init(delay: Swift.Duration = .milliseconds(300)) {
        self.delay = delay
    }

    func getLyrics(_ input: Operations.getLyrics.Input) async throws -> Operations.getLyrics.Output {
        try await Task.sleep(for: delay)
        return .ok(.init(body: .json(
            Components.Schemas.Record(
                id: 1,
                trackName: "Test Track",
                artistName: "Test Artist",
                albumName: "Test Album",
                instrumental: false,
                plainLyrics: "hello",
                syncedLyrics: nil
            )
        )))
    }

    func getLyricsByID(_ input: Operations.getLyricsByID.Input) async throws -> Operations.getLyricsByID.Output { fatalError("not implemented") }
    func searchLyrics(_ input: Operations.searchLyrics.Input) async throws -> Operations.searchLyrics.Output { fatalError("not implemented") }
    func requestChallenge(_ input: Operations.requestChallenge.Input) async throws -> Operations.requestChallenge.Output { fatalError("not implemented") }
    func publishLyrics(_ input: Operations.publishLyrics.Input) async throws -> Operations.publishLyrics.Output { fatalError("not implemented") }
}

/// Polls `jobRunner.status()` until the job leaves the `.running` state.
private func waitForCompletion(of jobRunner: JobRunner, timeout: Swift.Duration = .seconds(5)) async throws -> JobRunner.Snapshot {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        let snapshot = await jobRunner.status()
        if snapshot.state != .running { return snapshot }
        try await Task.sleep(for: .milliseconds(20))
    }
    return await jobRunner.status()
}

// MARK: - Tests

@Suite("JobRunner Tests")
struct JobRunnerTests {

    @Test("status starts idle")
    func statusStartsIdle() async throws {
        let jobRunner = JobRunner()
        let snapshot = await jobRunner.status()
        #expect(snapshot.state == .idle)
        #expect(snapshot.kind == nil)
    }

    @Test("scan job transitions from running to succeeded")
    func scanJobSucceeds() async throws {
        let jobRunner = JobRunner()
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let started = await jobRunner.startScan(path: tempDir.path, database: db)
        #expect(started == true)

        let final = try await waitForCompletion(of: jobRunner)
        #expect(final.state == .succeeded)
        #expect(final.kind == .scan)
    }

    @Test("scan job with a missing directory fails")
    func scanJobFailsForMissingDirectory() async throws {
        let jobRunner = JobRunner()
        let db = MusicDatabase(nilDatabase: ())

        let started = await jobRunner.startScan(path: "/nonexistent/\(UUID().uuidString)", database: db)
        #expect(started == true)

        let final = try await waitForCompletion(of: jobRunner)
        #expect(final.state == .failed)
        #expect(final.message != nil)
    }

    @Test("second startScan while running is rejected")
    func secondScanRejectedWhileRunning() async throws {
        let jobRunner = JobRunner()
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let musicDir = try makeSlowScanDirectory()
        defer { try? FileManager.default.removeItem(at: musicDir) }

        let firstStarted = await jobRunner.startScan(path: musicDir.path, database: db)
        let secondStarted = await jobRunner.startScan(path: musicDir.path, database: db)

        #expect(firstStarted == true)
        #expect(secondStarted == false)

        // Confirm the first scan was still genuinely in flight when the second call was
        // rejected, not that it happened to already be done (which would make this test
        // pass for the wrong reason).
        let statusRightAfter = await jobRunner.status()
        #expect(statusRightAfter.state == .running)

        _ = try await waitForCompletion(of: jobRunner)
    }

    @Test("fetch job with nothing to do succeeds immediately")
    func fetchJobNothingToDo() async throws {
        let jobRunner = JobRunner()
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let started = await jobRunner.startFetch(options: makeFetchOptions(), database: db)
        #expect(started == true)

        let final = try await waitForCompletion(of: jobRunner)
        #expect(final.state == .succeeded)
        #expect(final.kind == .fetch)
        #expect(final.message == "No songs need lyrics. Nothing to do.")
    }

    @Test("second startFetch while running is rejected")
    func secondFetchRejectedWhileRunning() async throws {
        let jobRunner = JobRunner()
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try await db.insertOrUpdateSong(makeLyarricsTrack(fileTrackPath: "/music/a.mp3"))

        let options = makeFetchOptions()
        let client = LRCLibClient(underlyingClient: SlowMockAPIClient())
        let firstStarted = await jobRunner.startFetch(options: options, database: db, client: client)
        let secondStarted = await jobRunner.startFetch(options: options, database: db, client: client)

        #expect(firstStarted == true)
        #expect(secondStarted == false)

        // Same rationale as the scan test above: confirm the rejection happened while the
        // first job was genuinely still running, not after it had already finished.
        let statusRightAfter = await jobRunner.status()
        #expect(statusRightAfter.state == .running)

        _ = try await waitForCompletion(of: jobRunner)
    }

    @Test("startFetch rejects invalid options via Fetch.validate()")
    func fetchJobFailsValidation() async throws {
        let jobRunner = JobRunner()
        let (db, tempDir) = try makeTestDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let started = await jobRunner.startFetch(options: makeFetchOptions(concurrency: 0), database: db)
        #expect(started == true)

        let final = try await waitForCompletion(of: jobRunner)
        #expect(final.state == .failed)
    }
}
