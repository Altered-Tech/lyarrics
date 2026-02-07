import ArgumentParser
import Hummingbird
import OpenAPIHummingbird

struct Serve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start the web server"
    )

    @Option(name: .shortAndLong, help: "The hostname to bind to")
    var hostname: String = "127.0.0.1"

    @Option(name: .shortAndLong, help: "The port to listen on")
    var port: Int = 8080

    func run() async throws {
        let router = Router()
        router.middlewares.add(LogRequestsMiddleware(.info))

        router.get("/") { request, context in
            return "<html>...</html>"
        }

        let app = Application(
            router: router,
            configuration: .init(address: .hostname(hostname, port: port))
        )

        try await app.runService()
    }
}