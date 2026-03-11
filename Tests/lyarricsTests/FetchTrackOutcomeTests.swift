import Testing
import Foundation
import OpenAPIRuntime
@testable import LRCLib
@testable import lyarrics
import Logging

// MARK: - Helpers

private struct AnyError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// A mock that always returns the same output or throws a given error.
private final class FixedMockAPIClient: APIProtocol, @unchecked Sendable {
    private let result: Result<Operations.getLyrics.Output, Error>

    init(output: Operations.getLyrics.Output) {
        self.result = .success(output)
    }

    init(throwing error: Error) {
        self.result = .failure(error)
    }

    func getLyrics(_ input: Operations.getLyrics.Input) async throws -> Operations.getLyrics.Output {
        try result.get()
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
    instrumental: Bool = false,
    plainLyrics: String? = nil,
    syncedLyrics: String? = nil
) -> Operations.getLyrics.Output {
    .ok(.init(body: .json(
        Components.Schemas.Record(
            id: 1,
            trackName: "Bohemian Rhapsody",
            artistName: "Queen",
            albumName: "A Night at the Opera",
            instrumental: instrumental,
            plainLyrics: plainLyrics,
            syncedLyrics: syncedLyrics
        )
    )))
}

private func makeNotFoundOutput() -> Operations.getLyrics.Output {
    .notFound(.init(body: .json(
        Components.Schemas._Error(statusCode: 404, message: "Not found", name: "TrackNotFound")
    )))
}

private func makeFetch() -> Fetch {
    var fetch = Fetch()
    fetch.maxRetries = 1
    fetch.delay = 0
    return fetch
}

// MARK: - fetchTrackOutcome Tests

@Suite("fetchTrackOutcome Tests")
struct FetchTrackOutcomeTests {

    private let logger = Logger(label: "test")
    private let track = makeLyarricsTrack()
    private let rateLimiter = RateLimiter(milliseconds: 0)

    @Test("returns .synced when syncedLyrics is present")
    func returnsSynced() async {
        let syncedContent = "[00:00.28] Is this the real life?"
        let mock = FixedMockAPIClient(output: makeOkOutput(syncedLyrics: syncedContent))
        let client = LRCLibClient(underlyingClient: mock)
        let fetch = makeFetch()

        let (returnedTrack, outcome) = await fetch.fetchTrackOutcome(track: track, client: client, rateLimiter: rateLimiter, logger: logger)

        guard case .synced(let content, _, _) = outcome else {
            Issue.record("Expected .synced, got \(outcome)")
            return
        }
        #expect(content == syncedContent)
        #expect(returnedTrack.fileTrackPath == track.fileTrackPath)
    }

    @Test("returns .plain when only plainLyrics is present")
    func returnsPlain() async {
        let plainContent = "Is this the real life?"
        let mock = FixedMockAPIClient(output: makeOkOutput(plainLyrics: plainContent))
        let client = LRCLibClient(underlyingClient: mock)
        let fetch = makeFetch()

        let (_, outcome) = await fetch.fetchTrackOutcome(track: track, client: client, rateLimiter: rateLimiter, logger: logger)

        guard case .plain(let content, _, _) = outcome else {
            Issue.record("Expected .plain, got \(outcome)")
            return
        }
        #expect(content == plainContent)
    }

    @Test("returns .synced over .plain when both are present")
    func syncedTakesPrecedenceOverPlain() async {
        let mock = FixedMockAPIClient(output: makeOkOutput(
            plainLyrics: "Is this the real life?",
            syncedLyrics: "[00:00.28] Is this the real life?"
        ))
        let client = LRCLibClient(underlyingClient: mock)
        let fetch = makeFetch()

        let (_, outcome) = await fetch.fetchTrackOutcome(track: track, client: client, rateLimiter: rateLimiter, logger: logger)

        guard case .synced = outcome else {
            Issue.record("Expected .synced, got \(outcome)")
            return
        }
    }

    @Test("returns .instrumental when record is instrumental with no lyrics")
    func returnsInstrumental() async {
        let mock = FixedMockAPIClient(output: makeOkOutput(instrumental: true))
        let client = LRCLibClient(underlyingClient: mock)
        let fetch = makeFetch()

        let (_, outcome) = await fetch.fetchTrackOutcome(track: track, client: client, rateLimiter: rateLimiter, logger: logger)

        guard case .instrumental = outcome else {
            Issue.record("Expected .instrumental, got \(outcome)")
            return
        }
    }

    @Test("returns .noLyrics when record has no lyrics and is not instrumental")
    func returnsNoLyrics() async {
        let mock = FixedMockAPIClient(output: makeOkOutput())
        let client = LRCLibClient(underlyingClient: mock)
        let fetch = makeFetch()

        let (_, outcome) = await fetch.fetchTrackOutcome(track: track, client: client, rateLimiter: rateLimiter, logger: logger)

        guard case .noLyrics = outcome else {
            Issue.record("Expected .noLyrics, got \(outcome)")
            return
        }
    }

    @Test("returns .notFound when LRCLIB returns 404")
    func returnsNotFound() async {
        let mock = FixedMockAPIClient(output: makeNotFoundOutput())
        let client = LRCLibClient(underlyingClient: mock)
        let fetch = makeFetch()

        let (_, outcome) = await fetch.fetchTrackOutcome(track: track, client: client, rateLimiter: rateLimiter, logger: logger)

        guard case .notFound = outcome else {
            Issue.record("Expected .notFound, got \(outcome)")
            return
        }
    }

    @Test("returns .apiError with status code when LRCLIB returns undocumented response")
    func returnsApiError() async {
        let mock = FixedMockAPIClient(output: .undocumented(statusCode: 503, .init()))
        let client = LRCLibClient(underlyingClient: mock)
        let fetch = makeFetch()

        let (_, outcome) = await fetch.fetchTrackOutcome(track: track, client: client, rateLimiter: rateLimiter, logger: logger)

        guard case .apiError(let code) = outcome else {
            Issue.record("Expected .apiError, got \(outcome)")
            return
        }
        #expect(code == 503)
    }

    @Test("returns .decodingError with 'Unknown decoding error' when no underlying error")
    func returnsDecodingErrorUnknown() async {
        let mock = FixedMockAPIClient(throwing: LRCError.decodingError(nil))
        let client = LRCLibClient(underlyingClient: mock)
        let fetch = makeFetch()

        let (_, outcome) = await fetch.fetchTrackOutcome(track: track, client: client, rateLimiter: rateLimiter, logger: logger)

        guard case .decodingError(let description) = outcome else {
            Issue.record("Expected .decodingError, got \(outcome)")
            return
        }
        #expect(description == "Unknown decoding error")
    }

    @Test("returns .unknownError when a non-LRCError is thrown after all retries")
    func returnsUnknownError() async {
        let errorMessage = "Network connection lost"
        let mock = FixedMockAPIClient(throwing: AnyError(message: errorMessage))
        let client = LRCLibClient(underlyingClient: mock)
        let fetch = makeFetch()

        let (_, outcome) = await fetch.fetchTrackOutcome(track: track, client: client, rateLimiter: rateLimiter, logger: logger)

        guard case .unknownError(let description) = outcome else {
            Issue.record("Expected .unknownError, got \(outcome)")
            return
        }
        #expect(description == errorMessage)
    }

    @Test("lrcURL has .lrc extension derived from track file path")
    func lrcURLDerivedFromTrackPath() async {
        let mock = FixedMockAPIClient(output: makeOkOutput(syncedLyrics: "[00:00.28] Is this the real life?"))
        let client = LRCLibClient(underlyingClient: mock)
        let fetch = makeFetch()
        let customTrack = makeLyarricsTrack(fileTrackPath: "/music/subfolder/song.flac")

        let (_, outcome) = await fetch.fetchTrackOutcome(track: customTrack, client: client, rateLimiter: rateLimiter, logger: logger)

        guard case .synced(_, let lrcURL, _) = outcome else {
            Issue.record("Expected .synced, got \(outcome)")
            return
        }
        #expect(lrcURL.pathExtension == "lrc")
        #expect(lrcURL.deletingPathExtension().lastPathComponent == "song")
    }

    @Test("isInstrumental flag is forwarded from record into .synced outcome")
    func instrumentalFlagForwardedInSynced() async {
        let mock = FixedMockAPIClient(output: makeOkOutput(instrumental: true, syncedLyrics: "[00:00.28] Instrumental"))
        let client = LRCLibClient(underlyingClient: mock)
        let fetch = makeFetch()

        let (_, outcome) = await fetch.fetchTrackOutcome(track: track, client: client, rateLimiter: rateLimiter, logger: logger)

        guard case .synced(_, _, let isInstrumental) = outcome else {
            Issue.record("Expected .synced, got \(outcome)")
            return
        }
        #expect(isInstrumental == true)
    }
}
