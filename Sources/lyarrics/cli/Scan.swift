
import ArgumentParser
import Foundation
import Logging

struct Scan: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Fetch lyrics from the command line"
    )

    private static let logger = Logger(label: "com.lyarrics.Scan")

    @Argument(help: "The path to scan")
    var path: String

    public func run() async throws {
        let logger = Self.logger

        let database = try MusicDatabase()
        let musicDirectory = URL(fileURLWithPath: path)
        let scanner = LibraryScanner(musicDirectory: musicDirectory, database: database)

        do {
            logger.info("Starting Scan.")
            let start: Date = .now
            try await scanner.scanLibrary()
            let finish: Date = .now
            logger.info("Scan Complete. Took \(finish.timeIntervalSince1970.rounded() - start.timeIntervalSince1970.rounded()) seconds")
        } catch TrackError.fileNotFound(let path) {
            logger.error("File not found at \(path)")
        } catch {
            logger.error("Some other error: \(error)")
        }
    }
}
