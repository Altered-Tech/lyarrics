import Testing
import Foundation
@testable import lyarrics

// MARK: - ExecutableFinder Tests

@Suite("ExecutableFinder Tests")
struct ExecutableFinderTests {

    @Test("finds a known executable in PATH")
    func findsCommonExecutable() {
        // 'ls' is universally available on macOS/Linux
        let url = findExecutable("ls")
        #expect(url != nil)
        #expect(url?.lastPathComponent == "ls")
    }

    @Test("returns nil for a non-existent executable")
    func returnsNilForMissingExecutable() {
        let url = findExecutable("this-executable-does-not-exist-\(UUID().uuidString)")
        #expect(url == nil)
    }

    @Test("found executable URL points to a real file")
    func foundExecutableExists() {
        guard let url = findExecutable("ls") else { return }
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}