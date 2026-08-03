enum LyricType: String, Codable {
    case synced
    case plain
    case instrumental
    /// Confirmed absent from LRCLIB (a 404 on lookup), as opposed to `nil` which means
    /// never attempted. Distinguishing the two stops `fetch` from re-querying LRCLIB for
    /// the same known-absent tracks on every run.
    case notFound
    /// LRCLIB has the track but no plain or synced lyrics have been submitted for it, and
    /// it isn't marked instrumental. Same rationale as `notFound`.
    case noLyricsAvailable
}
