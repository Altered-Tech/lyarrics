import Foundation
import os

class LibraryScanner {
    private let logger = Logger(subsystem: "com.lyarrics", category: "LibraryScanner")
    private let database: MusicDatabase
    private let musicDirectory: URL
    private var erroredFiles: [String] = []
    
    init(musicDirectory: URL, database: MusicDatabase) {
        self.musicDirectory = musicDirectory
        self.database = database
    }
    
    func scanLibrary() throws {
        logger.info("Starting library scan at \(self.musicDirectory.path, privacy: .public)")
        var count: Int = 0
        let fileManager = FileManager.default
        if !fileManager.directoryExists(atPath: musicDirectory.path()) {
            logger.error("Provided path does not exist.")
            throw TrackError.pathNotFound("Provided path does not exist: \(musicDirectory.absoluteString)")
        }
        
        let enumerator = fileManager.enumerator(
            at: musicDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        
        guard let enumerator = enumerator else {
            logger.warning("Could not create enumerator for \(self.musicDirectory.path, privacy: .public)")
            return
        }
        
        for case let fileURL as URL in enumerator {
            // Only process audio files
            guard MusicExtension(rawValue: fileURL.pathExtension.lowercased()) != nil else {
                continue
            }
            
            try processFile(at: fileURL)
            count += 1
        }
        logger.info("Scan complete. Processed \(count, privacy: .public) songs")
        logger.warning("Failed to process the following: \(self.erroredFiles.joined(separator: ", "), privacy: .public)")
    }
    
    private func processFile(at url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let modificationDate = attributes[.modificationDate] as? Date ?? Date()
        
        // Check if file exists in database and hasn't changed
        if let existingSong = try? database.getSongByPath(url.path),
           existingSong.lastModified >= modificationDate {
            logger.debug("Skipping unchanged file: \(url.lastPathComponent, privacy: .public)")
            return
        }

        logger.info("Processing file: \(url.lastPathComponent, privacy: .public)")
        do {
            let track = try extractMetadata(from: url.path)
            try database.insertOrUpdateSong(track)
        } catch TrackError.noMetadata(let error) {
            logger.error("No MetaData: \(error, privacy: .public)")
            erroredFiles.append(url.path)
        } catch TrackError.fileNotFound(let error) {
            logger.error("File Not Found: \(error, privacy: .public)")
            erroredFiles.append(url.path)
        } catch let error{
            logger.error("\(error.localizedDescription, privacy: .public)")
            erroredFiles.append(url.path)
        }
    }
    
    func extractMetadata(from path: String) throws -> Track {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: path) {
            throw TrackError.fileNotFound(path)
        }
        let process = Process()
        guard let ffprobeURL = findExecutable("ffprobe") else {
            throw TrackError.executableNotFound("ffprobe")
        }
        process.executableURL = ffprobeURL

        process.arguments = [
            "-v", "quiet",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            path
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()

        // Close the write end in the parent so readDataToEndOfFile gets EOF
        pipe.fileHandleForWriting.closeFile()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        pipe.fileHandleForReading.closeFile()

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let format = json["format"] as? [String: Any],
              let tags = format["tags"] as? [String: Any] else {
            logger.warning("No metadata found for: \(path, privacy: .public)")
            throw TrackError.noMetadata(path)
        }

        // Extract metadata (case-insensitive key matching)
        let title = tags.firstValue(forKeys: ["title", "TITLE"])
            ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let album = tags.firstValue(forKeys: ["album", "ALBUM"])
            ?? "Unknown Album"
        let artist = tags.firstValue(forKeys: ["artist", "ARTIST"])
            ?? "Unknown Artist"
        let durationStr = format["duration"] as? String ?? "0"
        let duration = Double(durationStr) ?? 0.0

        let trackNumStr = tags.firstValue(forKeys: ["track", "TRACK"])
        let trackNumber = trackNumStr.flatMap { Int($0.components(separatedBy: "/").first ?? "") }

        let fileName = URL(fileURLWithPath: path).lastPathComponent

        let lyrics = loadLyrics(for: path, extension: "lrc")
        let lrcPath = URL(fileURLWithPath: path).deletingPathExtension().appendingPathExtension("lrc")
        let lrcName = lrcPath.lastPathComponent

        // Synced lyrics contain timecodes like [00:16.41]
        let isSynced: Bool
        if let lyrics = lyrics {
            isSynced = lyrics.range(of: #"\[\d{2}:\d{2}\.\d{2}\]"#, options: .regularExpression) != nil
        } else {
            isSynced = false
        }

        let track = Track(
            fileTrackPath: path,
            fileTrackName: fileName,
            fileLyricPath: lyrics != nil ? lrcPath.path : nil,
            fileLyricName: lyrics != nil ? lrcName : nil,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            trackNumber: trackNumber,
            lyrics: lyrics,
            instrumental: false,
            isSyncedLyrics: isSynced,
            lastModified: Date()
        )

        return track
    }

    func loadLyrics(for audioPath: String, extension ext: String) -> String? {
        let url = URL(fileURLWithPath: audioPath)
        let lyricsPath = url.deletingPathExtension().appendingPathExtension(ext).path
        return try? String(contentsOfFile: lyricsPath, encoding: .utf8)
    }
}