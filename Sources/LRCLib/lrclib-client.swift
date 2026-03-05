
import OpenAPIAsyncHTTPClient
import OpenAPIRuntime
import Foundation

public struct LRCLibClient: @unchecked Sendable {

    private let userAgent: String = "Lyarrics/\(appVersion)"

    private let underlyingClient: any APIProtocol
    internal init(underlyingClient: any APIProtocol) {
        self.underlyingClient = underlyingClient
    }

    public init() {
        self.init(
            underlyingClient: Client(
                serverURL: URL(string: "https://lrclib.net")!,
                transport: AsyncHTTPClientTransport()
            )
        )
    }

    public func getLyrics(song: Song) async throws -> Record {
        let query: Operations.getLyrics.Input.Query = .init(
            track_name: song.track.query, 
            artist_name: song.artist.query, 
            album_name: song.album.query, 
            duration: song.duration.query)
        let headers: Operations.getLyrics.Input.Headers = .init(
            User_hyphen_Agent: .init(stringLiteral: userAgent), 
            accept: [.init(contentType: .json)])
        let response: Operations.getLyrics.Output = try await underlyingClient.getLyrics(query: query, headers: headers)

        switch response {
            case .ok(let result):
                do {
                    let json = try result.body.json
                    return Record(from: json)
                } catch let error as DecodingError {
                    throw LRCError.decodingError(error)
                }
            case .notFound(_):
                throw LRCError.notFound()
            case .undocumented(let statusCode, _):
                throw LRCError.undocumented(statusCode, "Undocumented status code")
        }
    }
}