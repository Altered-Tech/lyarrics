import Elementary
import Foundation

/// Shared page shell: HTML document skeleton, nav, and inline CSS (no external stylesheet or
/// build step, to keep the Docker image and "basic UI" scope unchanged).
struct Layout<Body: HTML>: HTMLDocument {
    var title: String
    @HTMLBuilder var pageContent: Body

    var head: some HTML {
        meta(.charset("utf-8"))
        meta(.name(.viewport), .content("width=device-width, initial-scale=1.0"))
        style { Self.css }
    }

    var body: some HTML {
        header(.class("site-header")) {
            nav {
                a(.href("/"), .class("brand")) { "lyarrics" }
                a(.href("/library")) { "Library" }
                a(.href("/settings")) { "Settings" }
            }
        }
        main {
            pageContent
        }
    }

    private static var css: String {
        """
        :root { color-scheme: light dark; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
            margin: 0;
            line-height: 1.4;
        }
        .site-header {
            border-bottom: 1px solid #8884;
            padding: 0.75rem 1.5rem;
        }
        .site-header nav { display: flex; gap: 1.25rem; align-items: baseline; }
        .site-header .brand { font-weight: 600; font-size: 1.1rem; }
        main { max-width: 60rem; margin: 0 auto; padding: 1.5rem; }
        a { color: #3b82f6; text-decoration: none; }
        a:hover { text-decoration: underline; }
        h1, h2 { margin-top: 0; }
        .panel { border: 1px solid #8884; border-radius: 0.5rem; padding: 1rem 1.25rem; margin-bottom: 1.5rem; }
        .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(8rem, 1fr)); gap: 0.75rem; margin-bottom: 1.5rem; }
        .stat-tile { border: 1px solid #8884; border-radius: 0.5rem; padding: 0.75rem 1rem; }
        .stat-tile .value { font-size: 1.5rem; font-weight: 600; display: block; }
        .stat-tile .label { font-size: 0.85rem; opacity: 0.7; }
        .action-form { display: flex; flex-wrap: wrap; gap: 0.75rem; align-items: center; margin-bottom: 0.75rem; }
        .action-form label { display: flex; gap: 0.35rem; align-items: center; font-size: 0.9rem; }
        table { width: 100%; border-collapse: collapse; }
        th, td { text-align: left; padding: 0.5rem 0.6rem; border-bottom: 1px solid #8884; }
        .badge { display: inline-block; padding: 0.15rem 0.5rem; border-radius: 1rem; font-size: 0.78rem; white-space: nowrap; }
        .badge-synced { background: #16a34a33; color: #16a34a; }
        .badge-plain { background: #2563eb33; color: #2563eb; }
        .badge-instrumental { background: #7c3aed33; color: #7c3aed; }
        .badge-notFound { background: #dc262633; color: #dc2626; }
        .badge-noLyricsAvailable { background: #ea580c33; color: #ea580c; }
        .badge-missing { background: #6b728033; color: #6b7280; }
        .search-form { display: flex; gap: 0.5rem; margin-bottom: 1rem; flex-wrap: wrap; }
        .pagination { display: flex; gap: 1rem; margin-top: 1rem; }
        pre.lyrics { white-space: pre-wrap; background: #8881; border-radius: 0.5rem; padding: 1rem; max-height: 32rem; overflow-y: auto; }
        .muted { opacity: 0.7; font-size: 0.9rem; }
        """
    }
}

/// Renders a colored status badge for a track's lyric state — `nil` means missing (never fetched).
struct LyricStatusBadge: HTML {
    let lyricType: LyricType?

    var body: some HTML {
        span(.class("badge \(cssClass)")) { label }
    }

    private var cssClass: String {
        switch lyricType {
        case .synced: "badge-synced"
        case .plain: "badge-plain"
        case .instrumental: "badge-instrumental"
        case .notFound: "badge-notFound"
        case .noLyricsAvailable: "badge-noLyricsAvailable"
        case nil: "badge-missing"
        }
    }

    private var label: String {
        switch lyricType {
        case .synced: "Synced"
        case .plain: "Plain"
        case .instrumental: "Instrumental"
        case .notFound: "Not Found"
        case .noLyricsAvailable: "No Lyrics"
        case nil: "Missing"
        }
    }
}

enum DurationFormatter {
    /// `Int(_:)` traps on non-finite or out-of-range input, so this guards defensively even
    /// though nothing in the current write path is known to produce NaN/infinite durations.
    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "-:--" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
