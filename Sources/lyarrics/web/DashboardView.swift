import Elementary

struct DashboardView: HTML {
    let details: MusicDetails
    let job: JobRunner.Snapshot
    let musicPath: String

    var body: some HTML {
        Layout(title: "lyarrics") {
            h1 { "Library Overview" }

            section(.class("stats")) {
                StatTile(label: "Songs", value: details.songs)
                StatTile(label: "Missing", value: details.missing)
                StatTile(label: "Synced", value: details.sync)
                StatTile(label: "Plain", value: details.plain)
                StatTile(label: "Instrumental", value: details.instrumental)
                StatTile(label: "Not Found on LRCLIB", value: details.notFound)
                StatTile(label: "No Lyrics Available", value: details.noLyricsAvailable)
            }

            section(.class("panel")) {
                h2 { "Job Status" }
                JobStatusSummary(job: job)
            }

            section(.class("panel")) {
                h2 { "Actions" }
                if job.state == .running {
                    p(.class("muted")) { "A job is already running — wait for it to finish before starting another." }
                }
                form(.action("/actions/scan"), .method(.post), .class("action-form")) {
                    label(.for("scan-path")) { "Scan directory" }
                    input(.type(.text), .name("path"), .id("scan-path"), .value(musicPath), .placeholder("/music"))
                        .attributes(.disabled, when: job.state == .running)
                    input(.type(.submit), .value("Start Scan"))
                        .attributes(.disabled, when: job.state == .running)
                }
                if musicPath.isEmpty {
                    p(.class("muted")) {
                        "No default music path set — "
                        a(.href("/settings")) { "set one in Settings" }
                        " to pre-fill this, or type a path above for a one-off scan."
                    }
                }
                form(.action("/actions/fetch"), .method(.post), .class("action-form")) {
                    label(.for("fetch-limit")) { "Limit (optional)" }
                    input(.type(.number), .name("limit"), .id("fetch-limit"), .placeholder("all"))
                        .attributes(.disabled, when: job.state == .running)
                    label {
                        input(.type(.checkbox), .name("upgradePlain"), .value("true"))
                            .attributes(.disabled, when: job.state == .running)
                        "Upgrade plain lyrics"
                    }
                    label {
                        input(.type(.checkbox), .name("recheckUnresolved"), .value("true"))
                            .attributes(.disabled, when: job.state == .running)
                        "Recheck unresolved"
                    }
                    input(.type(.submit), .value("Start Fetch"))
                        .attributes(.disabled, when: job.state == .running)
                }
            }

            p { a(.href("/library")) { "Browse library →" } }

            if job.state == .running {
                script { Self.pollScript }
            }
        }
    }

    /// While a job is running, poll its status and update the progress text in place — no full
    /// page reload until the job actually finishes, at which point one reload picks up the
    /// refreshed stats and re-enabled action buttons. Plain `fetch` + `setTimeout`, no framework.
    private static var pollScript: String {
        """
        (function poll() {
            fetch('/api/job-status').then(function (r) { return r.json(); }).then(function (job) {
                if (job.state === 'running') {
                    var el = document.getElementById('job-status-text');
                    if (el) { el.textContent = 'Running ' + (job.kind || 'job') + '\\u2026 ' + job.processed + '/' + job.total; }
                    setTimeout(poll, 2000);
                } else {
                    location.reload();
                }
            });
        })();
        """
    }
}

private struct StatTile: HTML {
    let label: String
    let value: Int

    var body: some HTML {
        div(.class("stat-tile")) {
            span(.class("value")) { "\(value)" }
            span(.class("label")) { label }
        }
    }
}

private struct JobStatusSummary: HTML {
    let job: JobRunner.Snapshot

    var body: some HTML {
        switch job.state {
        case .idle:
            p(.class("muted")) { "No job has run yet." }
        case .running:
            p(.id("job-status-text")) { "Running \(job.kind?.rawValue ?? "job")… \(job.processed)/\(job.total)" }
        case .succeeded:
            p { job.message ?? "Job finished." }
        case .failed:
            p(.class("muted")) { "Job failed: \(job.message ?? "unknown error")" }
        }
    }
}
