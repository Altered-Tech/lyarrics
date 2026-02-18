
import ArgumentParser
import Foundation

struct Scan: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Fetch lyrics from the command line"
    )

    @Argument(help: "The path to scan")
    var path: String

    public func run() async throws {
        let database = try MusicDatabase()
        let musicDirectory = URL(fileURLWithPath: path)
        let scanner = LibraryScanner(musicDirectory: musicDirectory, database: database)
        do {
            try await scanner.scanLibrary()
            print("Scan Complete")
        } catch TrackError.fileNotFound(let path) {
            print("File not found at \(path)")
        } catch {
            print("Some other error: \(error)")
        }
    }
}