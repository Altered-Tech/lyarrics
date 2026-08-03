import Testing
import Foundation
@testable import lyarrics

// MARK: - Dictionary Extension Tests

@Suite("Dictionary+firstValue Tests")
struct DictionaryFirstValueTests {

    @Test("returns value for first matching key")
    func firstMatchingKey() {
        let dict: [String: Any] = ["title": "My Song", "TITLE": "Ignored"]
        let result = dict.firstValue(forKeys: ["title", "TITLE"])
        #expect(result == "My Song")
    }

    @Test("falls back to second key when first is missing")
    func fallsBackToSecondKey() {
        let dict: [String: Any] = ["TITLE": "My Song"]
        let result = dict.firstValue(forKeys: ["title", "TITLE"])
        #expect(result == "My Song")
    }

    @Test("returns nil when no keys match")
    func noMatchReturnsNil() {
        let dict: [String: Any] = ["artist": "Queen"]
        let result = dict.firstValue(forKeys: ["title", "TITLE"])
        #expect(result == nil)
    }

    @Test("returns nil for empty dictionary")
    func emptyDictionaryReturnsNil() {
        let dict: [String: Any] = [:]
        let result = dict.firstValue(forKeys: ["title"])
        #expect(result == nil)
    }

    @Test("returns nil for empty keys array")
    func emptyKeysArrayReturnsNil() {
        let dict: [String: Any] = ["title": "My Song"]
        let result = dict.firstValue(forKeys: [])
        #expect(result == nil)
    }

    @Test("skips non-String values")
    func skipsNonStringValues() {
        let dict: [String: Any] = ["count": 42, "title": "My Song"]
        let result = dict.firstValue(forKeys: ["count", "title"])
        // "count" has an Int value, so it should be skipped
        #expect(result == "My Song")
    }

    @Test("matches a casing not explicitly listed in the keys array")
    func matchesUnlistedCasing() {
        // Only "title"/"TITLE" are requested, but the tag is capitalized "Title" —
        // a case-insensitive fallback should still find it instead of returning nil.
        let dict: [String: Any] = ["Title": "My Song"]
        let result = dict.firstValue(forKeys: ["title", "TITLE"])
        #expect(result == "My Song")
    }

    @Test("exact match still wins over a case-insensitive alternative")
    func exactMatchTakesPriorityOverCaseInsensitive() {
        let dict: [String: Any] = ["title": "Exact", "TiTlE": "Fallback"]
        let result = dict.firstValue(forKeys: ["title"])
        #expect(result == "Exact")
    }

    @Test("case-insensitive fallback deterministically picks the lexicographically-first key on collision")
    func caseInsensitiveFallbackIsDeterministic() {
        // Neither "TITLE" nor "Title" is an exact match for "title", so this exercises
        // the fallback scan. Dictionary iteration order is unspecified, so the result must
        // come from an explicit tie-break rather than whichever key happens to iterate first.
        let dict: [String: Any] = ["TITLE": "Upper", "Title": "Mixed"]
        let expectedKey = ["TITLE", "Title"].sorted()[0]
        let expectedValue = dict[expectedKey] as? String

        let result = dict.firstValue(forKeys: ["title"])

        #expect(result == expectedValue)
    }
}
