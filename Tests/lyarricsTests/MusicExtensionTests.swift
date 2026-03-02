import Testing
import Foundation
@testable import lyarrics

// MARK: - MusicExtension Tests

@Suite("MusicExtension Tests")
struct MusicExtensionTests {

    @Test("all expected formats are present")
    func expectedFormats() {
        let expected: Set<String> = ["mp3", "flac", "m4a", "wav", "ogg", "opus", "aac", "wma", "aiff"]
        let actual = Set(MusicExtension.allCases.map(\.rawValue))
        #expect(actual == expected)
    }

    @Test("mp3 extension is recognized")
    func mp3Recognized() {
        #expect(MusicExtension(rawValue: "mp3") != nil)
    }

    @Test("flac extension is recognized")
    func flacRecognized() {
        #expect(MusicExtension(rawValue: "flac") != nil)
    }

    @Test("unknown extension returns nil")
    func unknownExtension() {
        #expect(MusicExtension(rawValue: "txt") == nil)
        #expect(MusicExtension(rawValue: "pdf") == nil)
        #expect(MusicExtension(rawValue: "") == nil)
    }

    @Test("uppercase extension is not recognized (requires lowercased input)")
    func uppercaseNotRecognized() {
        #expect(MusicExtension(rawValue: "MP3") == nil)
        #expect(MusicExtension(rawValue: "FLAC") == nil)
    }
}