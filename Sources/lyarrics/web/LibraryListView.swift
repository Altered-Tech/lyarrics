import Elementary
import Foundation

struct LibraryListView: HTML {
    let records: [TrackRecord]
    let total: Int
    let page: Int
    let pageSize: Int
    let query: String
    let statusFilter: String

    var body: some HTML {
        Layout(title: "Library") {
            h1 { "Library" }

            form(.action("/library"), .method(.get), .class("search-form")) {
                input(.type(.search), .name("q"), .value(query), .placeholder("Search title, artist, or album"))
                select(.name("status")) {
                    statusOption(value: "", label: "All")
                    statusOption(value: "missing", label: "Missing")
                    statusOption(value: "synced", label: "Synced")
                    statusOption(value: "plain", label: "Plain")
                    statusOption(value: "instrumental", label: "Instrumental")
                    statusOption(value: "notFound", label: "Not Found")
                    statusOption(value: "noLyricsAvailable", label: "No Lyrics")
                }
                input(.type(.submit), .value("Search"))
            }

            p(.class("muted")) { "\(total) track(s)" }

            if records.isEmpty {
                p { "No tracks found." }
            } else {
                table {
                    thead {
                        tr {
                            th { "Title" }
                            th { "Artist" }
                            th { "Album" }
                            th { "Duration" }
                            th { "Status" }
                        }
                    }
                    tbody {
                        for record in records {
                            tr {
                                td { a(.href("/library/\(record.id)")) { record.track.title } }
                                td { record.track.artist }
                                td { record.track.album }
                                td { DurationFormatter.format(record.track.duration) }
                                td { LyricStatusBadge(lyricType: record.track.lyricType) }
                            }
                        }
                    }
                }
            }

            PaginationView(page: page, pageSize: pageSize, total: total, query: query, statusFilter: statusFilter)
        }
    }

    private func statusOption(value: String, label: String) -> some HTML<HTMLTag.option> {
        option(.value(value)) { label }
            .attributes(.selected, when: statusFilter == value)
    }
}

private struct PaginationView: HTML {
    let page: Int
    let pageSize: Int
    let total: Int
    let query: String
    let statusFilter: String

    private var totalPages: Int { max(1, Int((Double(total) / Double(pageSize)).rounded(.up))) }

    var body: some HTML {
        if totalPages > 1 {
            div(.class("pagination")) {
                if page > 1 {
                    a(.href(link(for: page - 1))) { "← Previous" }
                }
                span(.class("muted")) { "Page \(page) of \(totalPages)" }
                if page < totalPages {
                    a(.href(link(for: page + 1))) { "Next →" }
                }
            }
        }
    }

    private func link(for targetPage: Int) -> String {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "status", value: statusFilter),
            URLQueryItem(name: "page", value: "\(targetPage)"),
        ]
        return "/library?" + (components.percentEncodedQuery ?? "")
    }
}
