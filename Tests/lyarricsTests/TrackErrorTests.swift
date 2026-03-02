import Testing
import Foundation
@testable import lyarrics

// MARK: - TrackError Tests

@Suite("TrackError Tests")
struct TrackErrorTests {

    @Test("parseFailed includes path and detail in description")
    func parseFailedDescription() {
        let error = TrackError.parseFailed("/music/song.mp3", "invalid JSON")
        #expect(error.errorDescription?.contains("/music/song.mp3") == true)
        #expect(error.errorDescription?.contains("invalid JSON") == true)
    }

    @Test("titleNotFound includes path in description")
    func titleNotFoundDescription() {
        let error = TrackError.titleNotFound("/music/song.mp3")
        #expect(error.errorDescription?.contains("/music/song.mp3") == true)
    }

    @Test("albumNotFound includes path in description")
    func albumNotFoundDescription() {
        let error = TrackError.albumNotFound("/music/song.mp3")
        #expect(error.errorDescription?.contains("/music/song.mp3") == true)
    }

    @Test("artistNotFound includes path in description")
    func artistNotFoundDescription() {
        let error = TrackError.artistNotFound("/music/song.mp3")
        #expect(error.errorDescription?.contains("/music/song.mp3") == true)
    }

    @Test("noMetadata includes path in description")
    func noMetadataDescription() {
        let error = TrackError.noMetadata("/music/song.mp3")
        #expect(error.errorDescription?.contains("/music/song.mp3") == true)
    }

    @Test("executableNotFound includes name in description")
    func executableNotFoundDescription() {
        let error = TrackError.executableNotFound("ffprobe")
        #expect(error.errorDescription?.contains("ffprobe") == true)
    }

    @Test("fileNotFound includes path in description")
    func fileNotFoundDescription() {
        let error = TrackError.fileNotFound("/music/missing.mp3")
        #expect(error.errorDescription?.contains("/music/missing.mp3") == true)
    }

    @Test("pathNotFound includes path in description")
    func pathNotFoundDescription() {
        let error = TrackError.pathNotFound("/no/such/dir")
        #expect(error.errorDescription?.contains("/no/such/dir") == true)
    }

    @Test("all TrackErrors conform to Error")
    func allCasesAreErrors() {
        let errors: [any Error] = [
            TrackError.parseFailed("p", "d"),
            TrackError.titleNotFound("p"),
            TrackError.albumNotFound("p"),
            TrackError.artistNotFound("p"),
            TrackError.noMetadata("p"),
            TrackError.executableNotFound("ffprobe"),
            TrackError.fileNotFound("p"),
            TrackError.pathNotFound("p"),
        ]
        #expect(errors.count == 8)
    }
}