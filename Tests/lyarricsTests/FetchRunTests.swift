import Testing
import Foundation
import OpenAPIRuntime
@testable import LRCLib
@testable import lyarrics
import Logging

// MARK: - Helpers

/// Returns responses in the order they were provided. Safe for sequential
/// (concurrency=1) tests only — no locking on callCount.
private final class SequencedMockAPIClient: APIProtocol, @unchecked Sendable {
    private let responses: [Result<Operations.getLyrics.Output, Error>]
    private(set) var callCount = 0

    init(responses: [Result<Operations.getLyrics.Output, Error>]) {
        self.responses = responses
    }

    func getLyrics(_ input: Operations.getLyrics.Input) async throws -> Operations.getLyrics.Output {
        let index = callCount
        callCount += 1
        switch responses[index] {
        case .success(let output): return output
        case .failure(let error): throw error
        }
    }

    func getLyricsByID(_ input: Operations.getLyricsByID.Input) async throws -> Operations.getLyricsByID.Output { fatalError("not implemented") }
    func searchLyrics(_ input: Operations.searchLyrics.Input) async throws -> Operations.searchLyrics.Output { fatalError("not implemented") }
    func requestChallenge(_ input: Operations.requestChallenge.Input) async throws -> Operations.requestChallenge.Output { fatalError("not implemented") }
    func publishLyrics(_ input: Operations.publishLyrics.Input) async throws -> Operations.publishLyrics.Output { fatalError("not implemented") }
}

/// Always returns the same response regardless of call order — safe for concurrent tests.
private final class FixedMockAPIClient: APIProtocol, @unchecked Sendable {
    private let response: Result<Operations.getLyrics.Output, Error>

    init(output: Operations.getLyrics.Output) { self.response = .success(output) }

    func getLyrics(_ input: Operations.getLyrics.Input) async throws -> Operations.getLyrics.Output {
        try response.get()
    }

    func getLyricsByID(_ input: Operations.getLyricsByID.Input) async throws -> Operations.getLyricsByID.Output { fatalError("not implemented") }
    func searchLyrics(_ input: Operations.searchLyrics.Input) async throws -> Operations.searchLyrics.Output { fatalError("not implemented") }
    func requestChallenge(_ input: Operations.requestChallenge.Input) async throws -> Operations.requestChallenge.Output { fatalError("not implemented") }
    func publishLyrics(_ input: Operations.publishLyrics.Input) async throws -> Operations.publishLyrics.Output { fatalError("not implemented") }
}

private func makeOkResponse(
    syncedLyrics: String? = nil,
    plainLyrics: String? = nil,
    instrumental: Bool = false
) -> Result<Operations.getLyrics.Output, Error> {
    .success(.ok(.init(body: .json(
        Components.Schemas.Record(
            id: 1,
            trackName: "Test Track",
            artistName: "Test Artist",
            albumName: "Test Album",
            instrumental: instrumental,
            plainLyrics: plainLyrics,
            syncedLyrics: syncedLyrics
        )
    ))))
}

private func makeNotFoundResponse() -> Result<Operations.getLyrics.Output, Error> {
    .success(.notFound(.init(body: .json(
        Components.Schemas._Error(statusCode: 404, message: "Not found", name: "TrackNotFound")
    ))))
}

private func makeUndocumentedResponse(statusCode: Int) -> Result<Operations.getLyrics.Output, Error> {
    .success(.undocumented(statusCode: statusCode, .init()))
}

// MARK: - Tests

@Suite("Fetch.process Tests")
struct FetchRunTests {

    private let logger = Logger(label: "test")
    private let rateLimiter = RateLimiter(milliseconds: 0)

    // MARK: Empty library

    @Test("empty library returns zero counts")
    func emptyLibraryReturnsZeroCounts() async throws {
        let (fetch, db, tempDir, _) = try makeFetchTestSetup(count: 0)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let mock = SequencedMockAPIClient(responses: [])
        let client = LRCLibClient(underlyingClient: mock)

        let (fetched, failed) = try await fetch.process(
            songsNeedingLyrics: [],
            database: db,
            client: client,
            rateLimiter: rateLimiter,
            logger: logger
        )

        #expect(fetched == 0)
        #expect(failed == 0)
        #expect(mock.callCount == 0)
    }

    // MARK: Synced outcome

    @Test("synced outcome writes .lrc file and updates database")
    func syncedOutcomeWritesFileAndUpdatesDatabase() async throws {
        let (fetch, db, tempDir, tracks) = try makeFetchTestSetup(count: 1)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let syncedContent = "[00:00.28] Is this the real life?"
        let mock = SequencedMockAPIClient(responses: [makeOkResponse(syncedLyrics: syncedContent)])
        let client = LRCLibClient(underlyingClient: mock)

        let (fetched, failed) = try await fetch.process(
            songsNeedingLyrics: tracks,
            database: db,
            client: client,
            rateLimiter: rateLimiter,
            logger: logger
        )

        #expect(fetched == 1)
        #expect(failed == 0)

        let lrcURL = URL(fileURLWithPath: tracks[0].fileTrackPath)
            .deletingPathExtension().appendingPathExtension("lrc")
        #expect(FileManager.default.fileExists(atPath: lrcURL.path))
        let written = try String(contentsOf: lrcURL, encoding: .utf8)
        #expect(written == syncedContent)

        let updated = try db.getSongByPath(tracks[0].fileTrackPath)
        #expect(updated?.lyrics == syncedContent)
        #expect(updated?.isSyncedLyrics == true)
        #expect(updated?.instrumental == false)
        #expect(updated?.fileLyricPath == lrcURL.path)
        #expect(updated?.fileLyricName == lrcURL.lastPathComponent)
    }

    // MARK: Plain outcome

    @Test("plain outcome writes .lrc file and marks isSynced false in database")
    func plainOutcomeWritesFileAndUpdatesDatabase() async throws {
        let (fetch, db, tempDir, tracks) = try makeFetchTestSetup(count: 1)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plainContent = "Is this the real life?"
        let mock = SequencedMockAPIClient(responses: [makeOkResponse(plainLyrics: plainContent)])
        let client = LRCLibClient(underlyingClient: mock)

        let (fetched, failed) = try await fetch.process(
            songsNeedingLyrics: tracks,
            database: db,
            client: client,
            rateLimiter: rateLimiter,
            logger: logger
        )

        #expect(fetched == 1)
        #expect(failed == 0)

        let lrcURL = URL(fileURLWithPath: tracks[0].fileTrackPath)
            .deletingPathExtension().appendingPathExtension("lrc")
        #expect(FileManager.default.fileExists(atPath: lrcURL.path))
        let written = try String(contentsOf: lrcURL, encoding: .utf8)
        #expect(written == plainContent)

        let updated = try db.getSongByPath(tracks[0].fileTrackPath)
        #expect(updated?.lyrics == plainContent)
        #expect(updated?.isSyncedLyrics == false)
        #expect(updated?.instrumental == false)
    }

    // MARK: Instrumental outcome

    @Test("instrumental outcome updates database and does not write .lrc file")
    func instrumentalOutcomeUpdatesDatabaseWithoutFile() async throws {
        let (fetch, db, tempDir, tracks) = try makeFetchTestSetup(count: 1)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let mock = SequencedMockAPIClient(responses: [makeOkResponse(instrumental: true)])
        let client = LRCLibClient(underlyingClient: mock)

        let (fetched, failed) = try await fetch.process(
            songsNeedingLyrics: tracks,
            database: db,
            client: client,
            rateLimiter: rateLimiter,
            logger: logger
        )

        #expect(fetched == 1)
        #expect(failed == 0)

        let lrcURL = URL(fileURLWithPath: tracks[0].fileTrackPath)
            .deletingPathExtension().appendingPathExtension("lrc")
        #expect(!FileManager.default.fileExists(atPath: lrcURL.path))

        let updated = try db.getSongByPath(tracks[0].fileTrackPath)
        #expect(updated?.instrumental == true)
        #expect(updated?.lyrics == nil)
        #expect(updated?.fileLyricPath == nil)
    }

    // MARK: noLyrics outcome

    @Test("noLyrics outcome increments fetched and does not update database")
    func noLyricsOutcomeIncrementsFetchedOnly() async throws {
        let (fetch, db, tempDir, tracks) = try makeFetchTestSetup(count: 1)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let mock = SequencedMockAPIClient(responses: [makeOkResponse()])
        let client = LRCLibClient(underlyingClient: mock)

        let (fetched, failed) = try await fetch.process(
            songsNeedingLyrics: tracks,
            database: db,
            client: client,
            rateLimiter: rateLimiter,
            logger: logger
        )

        #expect(fetched == 1)
        #expect(failed == 0)

        let song = try db.getSongByPath(tracks[0].fileTrackPath)
        #expect(song?.lyrics == nil)
        #expect(song?.instrumental == false)
    }

    // MARK: notFound outcome

    @Test("notFound outcome increments failed count")
    func notFoundOutcomeIncrementsFailed() async throws {
        let (fetch, db, tempDir, tracks) = try makeFetchTestSetup(count: 1)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let mock = SequencedMockAPIClient(responses: [makeNotFoundResponse()])
        let client = LRCLibClient(underlyingClient: mock)

        let (fetched, failed) = try await fetch.process(
            songsNeedingLyrics: tracks,
            database: db,
            client: client,
            rateLimiter: rateLimiter,
            logger: logger
        )

        #expect(fetched == 0)
        #expect(failed == 1)
    }

    // MARK: apiError outcome

    @Test("apiError outcome increments failed count")
    func apiErrorOutcomeIncrementsFailed() async throws {
        let (fetch, db, tempDir, tracks) = try makeFetchTestSetup(count: 1)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let mock = SequencedMockAPIClient(responses: [makeUndocumentedResponse(statusCode: 503)])
        let client = LRCLibClient(underlyingClient: mock)

        let (fetched, failed) = try await fetch.process(
            songsNeedingLyrics: tracks,
            database: db,
            client: client,
            rateLimiter: rateLimiter,
            logger: logger
        )

        #expect(fetched == 0)
        #expect(failed == 1)
    }

    // MARK: decodingError / unknownError — neither counter incremented

    @Test("decodingError outcome does not increment fetched or failed")
    func decodingErrorNotCounted() async throws {
        let (fetch, db, tempDir, tracks) = try makeFetchTestSetup(count: 1)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let mock = SequencedMockAPIClient(responses: [.failure(LRCError.decodingError(nil))])
        let client = LRCLibClient(underlyingClient: mock)

        let (fetched, failed) = try await fetch.process(
            songsNeedingLyrics: tracks,
            database: db,
            client: client,
            rateLimiter: rateLimiter,
            logger: logger
        )

        #expect(fetched == 0)
        #expect(failed == 0)
    }

    // MARK: Dry run

    @Test("dryRun skips .lrc file write and database update for synced lyrics")
    func dryRunSkipsSyncedWrite() async throws {
        let (baseFetch, db, tempDir, tracks) = try makeFetchTestSetup(count: 1)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var fetch = baseFetch
        fetch.dryRun = true

        let mock = SequencedMockAPIClient(responses: [makeOkResponse(syncedLyrics: "[00:00.28] Test")])
        let client = LRCLibClient(underlyingClient: mock)

        let (fetched, _) = try await fetch.process(
            songsNeedingLyrics: tracks,
            database: db,
            client: client,
            rateLimiter: rateLimiter,
            logger: logger
        )

        #expect(fetched == 1)

        let lrcURL = URL(fileURLWithPath: tracks[0].fileTrackPath)
            .deletingPathExtension().appendingPathExtension("lrc")
        #expect(!FileManager.default.fileExists(atPath: lrcURL.path))

        let song = try db.getSongByPath(tracks[0].fileTrackPath)
        #expect(song?.lyrics == nil)
        #expect(song?.isSyncedLyrics == false)
    }

    @Test("dryRun skips database update for instrumental")
    func dryRunSkipsInstrumentalDatabaseUpdate() async throws {
        let (baseFetch, db, tempDir, tracks) = try makeFetchTestSetup(count: 1)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var fetch = baseFetch
        fetch.dryRun = true

        let mock = SequencedMockAPIClient(responses: [makeOkResponse(instrumental: true)])
        let client = LRCLibClient(underlyingClient: mock)

        _ = try await fetch.process(
            songsNeedingLyrics: tracks,
            database: db,
            client: client,
            rateLimiter: rateLimiter,
            logger: logger
        )

        let song = try db.getSongByPath(tracks[0].fileTrackPath)
        #expect(song?.instrumental == false)
    }

    // MARK: Multiple tracks

    @Test("multiple tracks processed with correct fetched and failed counts")
    func multipleTracksProcessed() async throws {
        let (fetch, db, tempDir, tracks) = try makeFetchTestSetup(count: 3)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Track 0 → synced, Track 1 → notFound, Track 2 → instrumental
        let mock = SequencedMockAPIClient(responses: [
            makeOkResponse(syncedLyrics: "[00:00.28] Track 0 lyrics"),
            makeNotFoundResponse(),
            makeOkResponse(instrumental: true),
        ])
        let client = LRCLibClient(underlyingClient: mock)

        let (fetched, failed) = try await fetch.process(
            songsNeedingLyrics: tracks,
            database: db,
            client: client,
            rateLimiter: rateLimiter,
            logger: logger
        )

        #expect(fetched == 2)
        #expect(failed == 1)
        #expect(mock.callCount == 3)
    }

    @Test("all tracks processed when count exceeds concurrency")
    func allTracksProcessedWhenExceedsConcurrency() async throws {
        let (baseFetch, db, tempDir, tracks) = try makeFetchTestSetup(count: 5)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Use a fixed mock (safe for concurrent access) with concurrency > 1
        var fetch = baseFetch
        fetch.concurrency = 2

        let fixedMock = FixedMockAPIClient(
            output: .ok(.init(body: .json(
                Components.Schemas.Record(
                    id: 1, trackName: "T", artistName: "A", albumName: "L",
                    instrumental: false, plainLyrics: "la la la", syncedLyrics: nil
                )
            )))
        )
        let client = LRCLibClient(underlyingClient: fixedMock)

        let (fetched, failed) = try await fetch.process(
            songsNeedingLyrics: tracks,
            database: db,
            client: client,
            rateLimiter: rateLimiter,
            logger: logger
        )

        #expect(fetched == 5)
        #expect(failed == 0)
    }
}
