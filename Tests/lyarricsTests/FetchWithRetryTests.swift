import Testing
import Foundation
import OpenAPIRuntime
@testable import LRCLib
@testable import lyarrics
import Logging

// MARK: - Helpers

private struct TransientError: Error, LocalizedError {
    var errorDescription: String? { "Transient network error" }
}

/// Thrown by `SequencedMockAPIClient` when called more times than it was configured for —
/// e.g. if retry logic wrongly retries something it shouldn't. Reported via `Issue.record`
/// so the failure reads as a normal assertion failure instead of an index-out-of-bounds trap.
private struct UnexpectedExtraCallError: Error {}

/// A mock that returns a pre-configured sequence of responses in order.
private final class SequencedMockAPIClient: APIProtocol, @unchecked Sendable {
    private let responses: [Result<Operations.getLyrics.Output, Error>]
    private(set) var callCount = 0

    init(responses: [Result<Operations.getLyrics.Output, Error>]) {
        self.responses = responses
    }

    func getLyrics(_ input: Operations.getLyrics.Input) async throws -> Operations.getLyrics.Output {
        let index = callCount
        callCount += 1
        guard index < responses.count else {
            Issue.record("SequencedMockAPIClient.getLyrics called \(callCount) time(s) but only \(responses.count) response(s) were configured")
            throw UnexpectedExtraCallError()
        }
        switch responses[index] {
        case .success(let output): return output
        case .failure(let error): throw error
        }
    }

    func getLyricsByID(_ input: Operations.getLyricsByID.Input) async throws -> Operations.getLyricsByID.Output {
        fatalError("Not implemented in mock")
    }

    func searchLyrics(_ input: Operations.searchLyrics.Input) async throws -> Operations.searchLyrics.Output {
        fatalError("Not implemented in mock")
    }

    func requestChallenge(_ input: Operations.requestChallenge.Input) async throws -> Operations.requestChallenge.Output {
        fatalError("Not implemented in mock")
    }

    func publishLyrics(_ input: Operations.publishLyrics.Input) async throws -> Operations.publishLyrics.Output {
        fatalError("Not implemented in mock")
    }
}

private func makeOkOutput(
    id: Int = 1,
    trackName: String = "Bohemian Rhapsody",
    artistName: String = "Queen",
    albumName: String = "A Night at the Opera",
    instrumental: Bool = false,
    plainLyrics: String? = "Is this the real life?",
    syncedLyrics: String? = "[00:00.28] Is this the real life?"
) -> Result<Operations.getLyrics.Output, Error> {
    .success(.ok(.init(body: .json(
        Components.Schemas.Record(
            id: id,
            trackName: trackName,
            artistName: artistName,
            albumName: albumName,
            instrumental: instrumental,
            plainLyrics: plainLyrics,
            syncedLyrics: syncedLyrics
        )
    ))))
}

private func makeNotFoundOutput() -> Result<Operations.getLyrics.Output, Error> {
    .success(.notFound(.init(body: .json(
        Components.Schemas._Error(statusCode: 404, message: "Not found", name: "TrackNotFound")
    ))))
}

private func makeUndocumentedOutput(statusCode: Int) -> Result<Operations.getLyrics.Output, Error> {
    .success(.undocumented(statusCode: statusCode, .init()))
}

private func makeSong() -> Song {
    Song(
        track: LRCLib.Track("Bohemian Rhapsody"),
        artist: Artist("Queen"),
        album: Album("A Night at the Opera"),
        duration: Duration(354)
    )
}

/// Constructs a `Fetch` instance with the given retry config and zero delay
/// so tests don't actually sleep.
private func makeFetch(maxRetries: Int = 3) -> Fetch {
    var fetch = Fetch()
    fetch.maxRetries = maxRetries
    fetch.delay = 0
    return fetch
}

// MARK: - fetchWithRetry Tests

@Suite("fetchWithRetry Tests")
struct FetchWithRetryTests {

    @Test("succeeds immediately on first attempt")
    func succeedsFirstAttempt() async throws {
        let mock = SequencedMockAPIClient(responses: [makeOkOutput()])
        let client = LRCLibClient(underlyingClient: mock)
        let fetch = makeFetch()

        let record = try await fetch.fetchWithRetry(client: client, song: makeSong(), logger: Logger(label: "test"))

        #expect(record.trackName == "Bohemian Rhapsody")
        #expect(mock.callCount == 1)
    }

    @Test("retries once on transient error then succeeds")
    func retriesOnTransientErrorThenSucceeds() async throws {
        let mock = SequencedMockAPIClient(responses: [
            .failure(TransientError()),
            makeOkOutput(),
        ])
        let client = LRCLibClient(underlyingClient: mock)
        let fetch = makeFetch(maxRetries: 3)

        let record = try await fetch.fetchWithRetry(client: client, song: makeSong(), logger: Logger(label: "test"))

        #expect(record.trackName == "Bohemian Rhapsody")
        #expect(mock.callCount == 2)
    }

    @Test("exhausts all retries and rethrows last error")
    func exhaustsAllRetries() async throws {
        let mock = SequencedMockAPIClient(responses: [
            .failure(TransientError()),
            .failure(TransientError()),
            .failure(TransientError()),
        ])
        let client = LRCLibClient(underlyingClient: mock)
        let fetch = makeFetch(maxRetries: 3)

        await #expect(throws: TransientError.self) {
            try await fetch.fetchWithRetry(client: client, song: makeSong(), logger: Logger(label: "test"))
        }
        #expect(mock.callCount == 3)
    }

    @Test("does not retry LRCError.notFound — propagates immediately")
    func doesNotRetryLRCError() async throws {
        let mock = SequencedMockAPIClient(responses: [
            makeNotFoundOutput(),
        ])
        let client = LRCLibClient(underlyingClient: mock)
        let fetch = makeFetch(maxRetries: 3)

        await #expect(throws: LRCError.self) {
            try await fetch.fetchWithRetry(client: client, song: makeSong(), logger: Logger(label: "test"))
        }
        #expect(mock.callCount == 1)
    }

    @Test("does not crash and behaves as a single attempt when maxRetries is 0")
    func maxRetriesZeroDoesNotCrash() async throws {
        // Regression test: `for attempt in 1...maxRetries` traps when maxRetries is 0
        // (an invalid Swift range). fetchWithRetry must clamp to at least one attempt.
        let mock = SequencedMockAPIClient(responses: [makeOkOutput()])
        let client = LRCLibClient(underlyingClient: mock)
        let fetch = makeFetch(maxRetries: 0)

        let record = try await fetch.fetchWithRetry(client: client, song: makeSong(), logger: Logger(label: "test"))

        #expect(record.trackName == "Bohemian Rhapsody")
        #expect(mock.callCount == 1)
    }

    @Test("retries on a 429 rate-limit response then succeeds")
    func retriesOn429ThenSucceeds() async throws {
        let mock = SequencedMockAPIClient(responses: [
            makeUndocumentedOutput(statusCode: 429),
            makeOkOutput(),
        ])
        let client = LRCLibClient(underlyingClient: mock)
        let fetch = makeFetch(maxRetries: 3)

        let record = try await fetch.fetchWithRetry(client: client, song: makeSong(), logger: Logger(label: "test"))

        #expect(record.trackName == "Bohemian Rhapsody")
        #expect(mock.callCount == 2)
    }

    @Test("retries on a 503 server error response then succeeds")
    func retriesOn503ThenSucceeds() async throws {
        let mock = SequencedMockAPIClient(responses: [
            makeUndocumentedOutput(statusCode: 503),
            makeOkOutput(),
        ])
        let client = LRCLibClient(underlyingClient: mock)
        let fetch = makeFetch(maxRetries: 3)

        let record = try await fetch.fetchWithRetry(client: client, song: makeSong(), logger: Logger(label: "test"))

        #expect(record.trackName == "Bohemian Rhapsody")
        #expect(mock.callCount == 2)
    }

    @Test("does not retry a non-retryable undocumented status code")
    func doesNotRetryNonRetryableStatusCode() async throws {
        let mock = SequencedMockAPIClient(responses: [
            makeUndocumentedOutput(statusCode: 400),
        ])
        let client = LRCLibClient(underlyingClient: mock)
        let fetch = makeFetch(maxRetries: 3)

        await #expect(throws: LRCError.self) {
            try await fetch.fetchWithRetry(client: client, song: makeSong(), logger: Logger(label: "test"))
        }
        #expect(mock.callCount == 1)
    }
}
