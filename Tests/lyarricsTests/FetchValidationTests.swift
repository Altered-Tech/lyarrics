import ArgumentParser
import Testing
@testable import lyarrics

// ArgumentParser's @Option/@Flag wrappers trap at runtime ("Can't read a value from a
// parsable argument definition") if a property is read without ever being explicitly
// assigned, even to its own default — so every property `validate()` touches must be
// set here, matching the convention already used by makeFetchTestSetup in FetchTestHelpers.swift.
private func makeValidFetch() -> Fetch {
    var fetch = Fetch()
    fetch.maxRetries = 3
    fetch.concurrency = 5
    fetch.delay = 500
    return fetch
}

/// Asserts `validate()` throws a `ValidationError` with exactly `expectedMessage` — not just
/// "some error" — so a bug that trips the wrong guard (and blames the wrong option) is caught
/// instead of silently passing because *a* error happened to get thrown.
private func expectValidationError(_ expectedMessage: String, from fetch: Fetch) {
    var fetch = fetch
    do {
        try fetch.validate()
        Issue.record("Expected validate() to throw \"\(expectedMessage)\" but it did not throw")
    } catch let error as ValidationError {
        #expect(error.message == expectedMessage)
    } catch {
        Issue.record("Expected a ValidationError with message \"\(expectedMessage)\", got \(type(of: error)): \(error)")
    }
}

@Suite("Fetch.validate Tests")
struct FetchValidationTests {

    @Test("rejects maxRetries less than 1")
    func rejectsMaxRetriesZero() {
        var fetch = makeValidFetch()
        fetch.maxRetries = 0
        expectValidationError("--max-retries must be at least 1.", from: fetch)
    }

    @Test("rejects negative concurrency")
    func rejectsNegativeConcurrency() {
        var fetch = makeValidFetch()
        fetch.concurrency = -1
        expectValidationError("--concurrency must be at least 1.", from: fetch)
    }

    @Test("rejects zero concurrency")
    func rejectsZeroConcurrency() {
        var fetch = makeValidFetch()
        fetch.concurrency = 0
        expectValidationError("--concurrency must be at least 1.", from: fetch)
    }

    @Test("rejects negative delay")
    func rejectsNegativeDelay() {
        var fetch = makeValidFetch()
        fetch.delay = -1
        expectValidationError("--delay must be zero or greater.", from: fetch)
    }

    @Test("accepts valid values")
    func acceptsValidValues() throws {
        var fetch = makeValidFetch()
        try fetch.validate()
    }
}
