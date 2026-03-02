import Testing
@testable import LRCLib

@Suite("LRCLib Model Tests")
struct ModelTests {

    // MARK: - Track

    @Test("Track stores title")
    func trackStoresTitle() {
        let track = Track("Bohemian Rhapsody")
        #expect(track.title == "Bohemian Rhapsody")
    }

    @Test("Track stores empty title")
    func trackStoresEmptyTitle() {
        let track = Track("")
        #expect(track.title == "")
    }

    // MARK: - Artist

    @Test("Artist stores name")
    func artistStoresName() {
        let artist = Artist("Queen")
        #expect(artist.name == "Queen")
    }

    // MARK: - Album

    @Test("Album stores name")
    func albumStoresName() {
        let album = Album("A Night at the Opera")
        #expect(album.name == "A Night at the Opera")
    }

    // MARK: - Duration

    @Test("Duration stores seconds")
    func durationStoresSeconds() {
        let duration = Duration(354)
        #expect(duration.seconds == 354)
    }

    @Test("Duration stores zero seconds")
    func durationStoresZero() {
        let duration = Duration(0)
        #expect(duration.seconds == 0)
    }

    // MARK: - Song

    @Test("Song stores all components")
    func songStoresAllComponents() {
        let song = Song(
            track: Track("Bohemian Rhapsody"),
            artist: Artist("Queen"),
            album: Album("A Night at the Opera"),
            duration: Duration(354)
        )
        #expect(song.track.title == "Bohemian Rhapsody")
        #expect(song.artist.name == "Queen")
        #expect(song.album.name == "A Night at the Opera")
        #expect(song.duration.seconds == 354)
    }

    // MARK: - LRCError

    @Test("LRCError notFound with no message")
    func lrcErrorNotFoundNoMessage() {
        let error = LRCError.notFound()
        guard case .notFound(let msg) = error else {
            Issue.record("Expected .notFound case")
            return
        }
        #expect(msg == nil)
    }

    @Test("LRCError notFound with message")
    func lrcErrorNotFoundWithMessage() {
        let error = LRCError.notFound("Track not found")
        guard case .notFound(let msg) = error else {
            Issue.record("Expected .notFound case")
            return
        }
        #expect(msg == "Track not found")
    }

    @Test("LRCError undocumented stores status code")
    func lrcErrorUndocumentedStatusCode() {
        let error = LRCError.undocumented(503)
        guard case .undocumented(let statusCode, _) = error else {
            Issue.record("Expected .undocumented case")
            return
        }
        #expect(statusCode == 503)
    }

    @Test("LRCError undocumented stores message")
    func lrcErrorUndocumentedMessage() {
        let error = LRCError.undocumented(503, "Service unavailable")
        guard case .undocumented(_, let msg) = error else {
            Issue.record("Expected .undocumented case")
            return
        }
        #expect(msg == "Service unavailable")
    }

    @Test("LRCError decodingError with no inner error")
    func lrcErrorDecodingErrorNoInner() {
        let error = LRCError.decodingError()
        guard case .decodingError(let inner) = error else {
            Issue.record("Expected .decodingError case")
            return
        }
        #expect(inner == nil)
    }

    @Test("LRCError is Error type")
    func lrcErrorIsErrorType() {
        let _: any Error = LRCError.notFound()
        let _: any Error = LRCError.undocumented(500)
        let _: any Error = LRCError.decodingError()
    }
}
