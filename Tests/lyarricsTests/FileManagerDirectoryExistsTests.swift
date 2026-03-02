import Testing
import Foundation
@testable import lyarrics

// MARK: - FileManager Extension Tests

@Suite("FileManager+directoryExists Tests")
struct FileManagerDirectoryExistsTests {

    @Test("returns true for an existing directory")
    func existingDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyarricsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        #expect(FileManager.default.directoryExists(atPath: tempDir.path) == true)
    }

    @Test("returns false for a non-existent path")
    func nonExistentPath() {
        #expect(FileManager.default.directoryExists(atPath: "/no/such/path/\(UUID().uuidString)") == false)
    }

    @Test("returns false for a file (not a directory)")
    func fileNotDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyarricsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.appendingPathComponent("file.txt").path
        FileManager.default.createFile(atPath: filePath, contents: nil)

        #expect(FileManager.default.directoryExists(atPath: filePath) == false)
    }
}