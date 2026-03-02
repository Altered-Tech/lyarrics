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
}