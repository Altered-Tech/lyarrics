import Testing
import Foundation
@testable import lyarrics

@Suite("RateLimiter Tests")
struct RateLimiterTests {

    // MARK: - First call

    @Test("first throttle call returns immediately")
    func firstCallIsImmediate() async throws {
        let limiter = RateLimiter(milliseconds: 500)
        let start = Date()
        try await limiter.throttle()
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 0.1, "First call should not sleep; elapsed: \(elapsed)s")
    }

    // MARK: - Sequential calls

    @Test("second throttle call waits at least delay ms")
    func secondCallWaits() async throws {
        let delayMs = 200
        let limiter = RateLimiter(milliseconds: delayMs)
        try await limiter.throttle() // first — immediate
        let start = Date()
        try await limiter.throttle() // second — should wait ~delay ms
        let elapsed = Date().timeIntervalSince(start)
        let minExpected = Double(delayMs) / 1000.0
        #expect(
            elapsed >= minExpected - 0.02,
            "Second call should wait ~\(delayMs)ms; elapsed: \(elapsed)s"
        )
    }

    @Test("third sequential call waits at least 2× delay ms total")
    func thirdCallWaits() async throws {
        let delayMs = 100
        let limiter = RateLimiter(milliseconds: delayMs)
        try await limiter.throttle() // first — immediate
        let start = Date()
        try await limiter.throttle() // ~delay ms
        try await limiter.throttle() // ~2× delay ms
        let elapsed = Date().timeIntervalSince(start)
        let minExpected = 2.0 * Double(delayMs) / 1000.0
        #expect(
            elapsed >= minExpected - 0.02,
            "Two sequential waits should take ~\(2 * delayMs)ms; elapsed: \(elapsed)s"
        )
    }

    // MARK: - Call after natural pause

    @Test("call after sufficient pause returns immediately")
    func callAfterPauseIsImmediate() async throws {
        let delayMs = 100
        let limiter = RateLimiter(milliseconds: delayMs)
        try await limiter.throttle() // first — immediate
        // Wait longer than the delay so the limiter's window has expired
        try await Task.sleep(nanoseconds: UInt64(Double(delayMs) * 2 * 1_000_000))
        let start = Date()
        try await limiter.throttle()
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 0.05, "Call after sufficient pause should be immediate; elapsed: \(elapsed)s")
    }

    // MARK: - Concurrent callers

    @Test("concurrent callers each get a unique staggered slot")
    func concurrentCallersGetUniqueSlots() async throws {
        let delayMs = 100
        let count = 4
        let limiter = RateLimiter(milliseconds: delayMs)
        let start = Date()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<count {
                group.addTask { try await limiter.throttle() }
            }
            try await group.waitForAll()
        }
        let elapsed = Date().timeIntervalSince(start)
        // N concurrent callers claim N sequential slots: total ≥ (N-1) × delay
        let minExpected = Double(count - 1) * Double(delayMs) / 1000.0
        #expect(
            elapsed >= minExpected - 0.05,
            "Concurrent callers should stagger; elapsed: \(elapsed)s, expected >= \(minExpected)s"
        )
    }
}
