import Foundation

struct Track: Codable {
    let fileTrackPath: String
    let fileTrackName: String
    let fileLyricPath: String?
    let fileLyricName: String?
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let trackNumber: Int?
    let lyrics: String?
    let instrumental: Bool
    let isSyncedLyrics: Bool
    let lastModified: Date
}