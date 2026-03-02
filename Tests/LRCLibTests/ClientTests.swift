import Testing
import OpenAPIRuntime
@testable import LRCLib

// MARK: - Mock

/// A mock implementation of APIProtocol for testing LRCLibClient.
final class MockAPIClient: APIProtocol, @unchecked Sendable {
    var getLyricsOutput: Operations.getLyrics.Output

    init(getLyricsOutput: Operations.getLyrics.Output) {
        self.getLyricsOutput = getLyricsOutput
    }

    func getLyrics(_ input: Operations.getLyrics.Input) async throws -> Operations.getLyrics.Output {
        getLyricsOutput
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

// MARK: - Helpers

private func makeSong(
    title: String = "Bohemian Rhapsody",
    artist: String = "Queen",
    album: String = "A Night at the Opera",
    duration: Int = 354
) -> Song {
    Song(
        track: Track(title),
        artist: Artist(artist),
        album: Album(album),
        duration: Duration(duration)
    )
}

private func makeSchemaRecord(
    id: Int = 1,
    trackName: String = "Bohemian Rhapsody",
    artistName: String = "Queen",
    albumName: String = "A Night at the Opera",
    instrumental: Bool = false,
    plainLyrics: String? = "Is this the real life?",
    syncedLyrics: String? = "[00:00.28] Is this the real life?"
) -> Components.Schemas.Record {
    Components.Schemas.Record(
        id: id,
        trackName: trackName,
        artistName: artistName,
        albumName: albumName,
        instrumental: instrumental,
        plainLyrics: plainLyrics,
        syncedLyrics: syncedLyrics
    )
}

private func makeNotFoundOutput() -> Operations.getLyrics.Output {
    .notFound(.init(body: .json(
        Components.Schemas._Error(
            statusCode: 404,
            message: "Failed to find specified track",
            name: "TrackNotFound"
        )
    )))
}

// MARK: - Tests

@Suite("LRCLibClient Tests")
struct ClientTests {

    @Test("public init creates a client without crashing")
    func publicInitSucceeds() {
        let client = LRCLibClient()
        _ = client
    }

    @Test("getLyrics returns Record on success")
    func getLyricsSuccess() async throws {
        let schema = makeSchemaRecord()
        let mock = MockAPIClient(getLyricsOutput: .ok(.init(body: .json(schema))))
        let client = LRCLibClient(underlyingClient: mock)

        let result = try await client.getLyrics(song: makeSong())

        #expect(result.id == schema.id)
        #expect(result.trackName == schema.trackName)
        #expect(result.artistName == schema.artistName)
        #expect(result.albumName == schema.albumName)
        #expect(result.instrumental == schema.instrumental)
        #expect(result.plainLyrics == schema.plainLyrics)
        #expect(result.syncedLyrics == schema.syncedLyrics)
    }

    @Test("getLyrics returns Record for instrumental track")
    func getLyricsInstrumental() async throws {
        let schema = makeSchemaRecord(instrumental: true, plainLyrics: nil, syncedLyrics: nil)
        let mock = MockAPIClient(getLyricsOutput: .ok(.init(body: .json(schema))))
        let client = LRCLibClient(underlyingClient: mock)

        let result = try await client.getLyrics(song: makeSong())

        #expect(result.instrumental == true)
        #expect(result.plainLyrics == nil)
        #expect(result.syncedLyrics == nil)
    }

    @Test("getLyrics throws notFound when track does not exist")
    func getLyricsNotFound() async throws {
        let mock = MockAPIClient(getLyricsOutput: makeNotFoundOutput())
        let client = LRCLibClient(underlyingClient: mock)

        await #expect(throws: LRCError.self) {
            try await client.getLyrics(song: makeSong())
        }
    }

    @Test("getLyrics throws LRCError.notFound on 404")
    func getLyricsNotFoundErrorType() async throws {
        let mock = MockAPIClient(getLyricsOutput: makeNotFoundOutput())
        let client = LRCLibClient(underlyingClient: mock)

        do {
            _ = try await client.getLyrics(song: makeSong())
            Issue.record("Expected error to be thrown")
        } catch let error as LRCError {
            guard case .notFound = error else {
                Issue.record("Expected .notFound, got \(error)")
                return
            }
        }
    }

    @Test("getLyrics throws LRCError.undocumented on unexpected status code")
    func getLyricsUndocumented() async throws {
        let mock = MockAPIClient(getLyricsOutput: .undocumented(statusCode: 503, .init()))
        let client = LRCLibClient(underlyingClient: mock)

        do {
            _ = try await client.getLyrics(song: makeSong())
            Issue.record("Expected error to be thrown")
        } catch let error as LRCError {
            guard case .undocumented(let code, _) = error else {
                Issue.record("Expected .undocumented, got \(error)")
                return
            }
            #expect(code == 503)
        }
    }
}
