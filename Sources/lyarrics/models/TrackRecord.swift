import Foundation

/// A `Track` paired with its database row id, for contexts (like the web UI) that need
/// a stable, URL-safe identifier — `Track` itself has no `id` since it's also the shape
/// used before a row exists (scanning).
struct TrackRecord: Codable, Sendable {
    let id: Int64
    let track: Track
}

enum LibraryFilter: Sendable {
    case all
    case missing
    case type(LyricType)
}
