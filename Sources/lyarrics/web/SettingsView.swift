import Elementary

struct SettingsView: HTML {
    let musicPath: String
    let saved: Bool

    var body: some HTML {
        Layout(title: "Settings") {
            h1 { "Settings" }

            if saved {
                p(.class("panel")) { "Saved." }
            }

            section(.class("panel")) {
                h2 { "Music library path" }
                p(.class("muted")) {
                    "Used to pre-fill the scan path on the dashboard. Falls back to the "
                    code { "LYARRICS_MUSIC_PATH" }
                    " environment variable (handy for Docker) until you save one here."
                }
                form(.action("/actions/settings"), .method(.post), .class("action-form")) {
                    label(.for("music-path")) { "Path" }
                    input(.type(.text), .name("musicPath"), .id("music-path"), .value(musicPath), .placeholder("/music"))
                    input(.type(.submit), .value("Save"))
                }
            }
        }
    }
}
