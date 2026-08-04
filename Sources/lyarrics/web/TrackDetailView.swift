import Elementary

struct TrackDetailView: HTML {
    let record: TrackRecord

    var body: some HTML {
        Layout(title: record.track.title) {
            p { a(.href("/library")) { "← Back to library" } }

            h1 { record.track.title }
            p { "\(record.track.artist) — \(record.track.album)" }
            p { LyricStatusBadge(lyricType: record.track.lyricType) }

            table {
                tbody {
                    detailRow(label: "Duration", value: DurationFormatter.format(record.track.duration))
                    if let trackNumber = record.track.trackNumber {
                        detailRow(label: "Track number", value: "\(trackNumber)")
                    }
                    detailRow(label: "Audio file", value: record.track.fileTrackPath)
                    if let lyricPath = record.track.fileLyricPath {
                        detailRow(label: "Lyrics file", value: lyricPath)
                    }
                }
            }

            if let lyrics = record.track.lyrics {
                h2 { "Lyrics" }
                pre(.class("lyrics")) { lyrics }
            }
        }
    }

    private func detailRow(label: String, value: String) -> some HTML<HTMLTag.tr> {
        tr {
            th { label }
            td { value }
        }
    }
}

struct TrackNotFoundView: HTML {
    var body: some HTML {
        Layout(title: "Not Found") {
            h1 { "Track not found" }
            p { a(.href("/library")) { "← Back to library" } }
        }
    }
}
