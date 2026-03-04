
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
            let startMessage: String = "Starting Scan."
            logger.info(Logger.Message(stringLiteral: startMessage))
            print(startMessage)
            let start: Date = .now
            try await scanner.scanLibrary { completed, total in
                let width = 30
                let filled = Int(Double(completed) / Double(total) * Double(width))
                let bar = String(repeating: "=", count: filled) + String(repeating: " ", count: width - filled)
                print("\r[\(bar)] \(completed)/\(total)", terminator: "")
                FileHandle.standardOutput.synchronizeFile()
            }
            print()
            let finish: Date = .now
            let endMessage: String = "Scan Complete. Took \(finish.timeIntervalSince1970.rounded() - start.timeIntervalSince1970.rounded()) seconds"
            logger.info(Logger.Message(stringLiteral: endMessage))
            print(endMessage)
        } catch TrackError.fileNotFound(let path) {
            logger.error("File not found at \(path)")
        } catch {
            logger.error("Some other error: \(error)")
        }
    }
}
