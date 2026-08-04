import ArgumentParser
import Foundation
import Hummingbird
import HummingbirdElementary

struct Serve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start the web server"
    )

    @Option(name: .shortAndLong, help: "The hostname to bind to")
    var hostname: String = "127.0.0.1"

    @Option(name: .shortAndLong, help: "The port to listen on")
    var port: Int = 8080

    /// Tracks change together, so route closures below can reference it in `LibraryFilter`.
    private static let statusFilterValues: [String: LibraryFilter] = [
        "missing": .missing,
        "synced": .type(.synced),
        "plain": .type(.plain),
        "instrumental": .type(.instrumental),
        "notFound": .type(.notFound),
        "noLyricsAvailable": .type(.noLyricsAvailable),
    ]

    private static let libraryPageSize = 25

    func run() async throws {
        let router = Router()
        router.middlewares.add(LogRequestsMiddleware(.info))

        let database = try MusicDatabase()
        let jobRunner = JobRunner()

        registerDashboardRoutes(router, database: database, jobRunner: jobRunner)
        registerLibraryRoutes(router, database: database)
        registerSettingsRoutes(router, database: database)
        registerActionRoutes(router, database: database, jobRunner: jobRunner)

        let app = Application(
            router: router,
            configuration: .init(address: .hostname(hostname, port: port))
        )

        try await app.runService()
    }

    // MARK: - Dashboard

    private func registerDashboardRoutes(_ router: Router<some RequestContext>, database: MusicDatabase, jobRunner: JobRunner) {
        router.get("/") { _, _ in
            let details = try await database.getMusicDetails() ?? MusicDetails(
                songs: 0, lyrics: 0, plain: 0, sync: 0, instrumental: 0, missing: 0, notFound: 0, noLyricsAvailable: 0
            )
            let job = await jobRunner.status()
            let musicPath = try await database.getMusicPath()
            return HTMLResponse { DashboardView(details: details, job: job, musicPath: musicPath) }
        }

        router.get("/api/job-status") { _, _ in
            await jobRunner.status()
        }
    }

    // MARK: - Library

    private func registerLibraryRoutes(_ router: Router<some RequestContext>, database: MusicDatabase) {
        router.get("/library") { request, _ in
            let query = request.uri.queryParameters.get("q") ?? ""
            let statusRaw = request.uri.queryParameters.get("status") ?? ""
            let page = max(1, request.uri.queryParameters.get("page", as: Int.self) ?? 1)
            let filter = Self.statusFilterValues[statusRaw] ?? .all

            let (records, total) = try await database.getSongsPaged(
                offset: (page - 1) * Self.libraryPageSize,
                limit: Self.libraryPageSize,
                query: query.isEmpty ? nil : query,
                filter: filter
            )
            return HTMLResponse {
                LibraryListView(records: records, total: total, page: page, pageSize: Self.libraryPageSize, query: query, statusFilter: statusRaw)
            }
        }

        router.get("/library/:id") { _, context in
            guard let id = context.parameters.get("id", as: Int64.self),
                  let record = try await database.getSongByID(id) else {
                return HTMLResponse(status: .notFound) { TrackNotFoundView() }
            }
            return HTMLResponse { TrackDetailView(record: record) }
        }
    }

    // MARK: - Settings

    private func registerSettingsRoutes(_ router: Router<some RequestContext>, database: MusicDatabase) {
        router.get("/settings") { request, _ in
            let musicPath = try await database.getMusicPath()
            let saved = request.uri.queryParameters.get("saved") == "1"
            return HTMLResponse { SettingsView(musicPath: musicPath, saved: saved) }
        }
    }

    // MARK: - Actions

    private func registerActionRoutes(_ router: Router<some RequestContext>, database: MusicDatabase, jobRunner: JobRunner) {
        router.post("/actions/settings") { request, _ in
            let form = try await Self.readForm(from: request)
            try await database.setMusicPath(form["musicPath"] ?? "")
            return Response(status: .seeOther, headers: [.location: "/settings?saved=1"])
        }

        router.post("/actions/scan") { request, _ in
            let form = try await Self.readForm(from: request)
            if let path = form["path"], !path.isEmpty {
                await jobRunner.startScan(path: path, database: database)
            }
            return Response(status: .seeOther, headers: [.location: "/"])
        }

        router.post("/actions/fetch") { request, _ in
            let form = try await Self.readForm(from: request)

            var fetchCommand = Fetch.makeDefault()
            fetchCommand.limit = form["limit"].flatMap(Int.init)
            fetchCommand.upgradePlain = form["upgradePlain"] != nil
            fetchCommand.recheckUnresolved = form["recheckUnresolved"] != nil

            await jobRunner.startFetch(options: fetchCommand, database: database)
            return Response(status: .seeOther, headers: [.location: "/"])
        }
    }

    /// Reads and parses an `application/x-www-form-urlencoded` request body.
    private static func readForm(from request: Request) async throws -> [String: String] {
        var request = request
        let buffer = try await request.collectBody(upTo: 1024 * 1024)
        let body = String(buffer: buffer)

        guard let items = URLComponents(string: "?" + body)?.queryItems else { return [:] }
        var result: [String: String] = [:]
        for item in items {
            result[item.name] = item.value ?? ""
        }
        return result
    }
}
