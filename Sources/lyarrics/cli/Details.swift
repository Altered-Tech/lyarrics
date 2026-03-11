import ArgumentParser
import Foundation
import Logging

struct Details: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "details",
        abstract: "Show details of your music library lyrics"
    )

    private static let logger = Logger(label: "com.lyarrics.Details")

    public func run() async throws {
        let logger = Self.logger

        let database = try MusicDatabase()

        logger.info("Getting details")
        guard let details: MusicDetails = try database.getMusicDetails() else {
            print("No database details")
            return
        }

        details.show()
    }
}