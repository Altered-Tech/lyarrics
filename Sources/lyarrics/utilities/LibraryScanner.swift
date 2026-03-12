import Foundation
import Logging

final class LibraryScanner: @unchecked Sendable {
    private let logger = Logger(label: "com.lyarrics.LibraryScanner")
    private let database: MusicDatabase
    private let musicDirectory: URL
    private var erroredFiles: [String] = []

    init(musicDirectory: URL, database: MusicDatabase) {
        self.musicDirectory = musicDirectory
        self.database = database
    }

    func scanLibrary(onProgress: ((Int, Int) -> Void)? = nil) async throws {
        logger.info("Starting library scan at \(self.musicDirectory.path)")
        let fileManager = FileManager.default
        if !fileManager.directoryExists(atPath: musicDirectory.path()) {
            logger.error("Provided path does not exist.")
            throw TrackError.pathNotFound("Provided path does not exist: \(musicDirectory.absoluteString)")
        }

        // Pre-load all known paths and their modification dates in one query
        let existingPaths = try database.getAllPathsAndDates()
        logger.info("Database has \(existingPaths.count) tracked files")

        // Enumerate synchronously (enumerator is unavailable from async contexts)
        let enumeratingMessage: String = "Enumerating files in \(self.musicDirectory.path)... This could take a bit..."
        logger.info(Logger.Message(stringLiteral: enumeratingMessage))
        print(enumeratingMessage)
        let audioFiles = collectFilesToProcess(existingPaths: existingPaths)
        let total = audioFiles.count
        logger.info("\(total) files need processing (\(existingPaths.count) unchanged, skipped)")

        guard total > 0 else {
            logger.info("Nothing to do — library is up to date")
            return
        }

        // Process ffprobe calls in parallel, bounded by processor count
        let maxConcurrency = ProcessInfo.processInfo.processorCount
        logger.info("Extracting metadata using \(maxConcurrency) parallel workers")
        var tracksToInsert: [Track] = []
        var errors: [String] = []
        var index = 0
        var completed = 0

        try await withThrowingTaskGroup(of: (Track?, String?, String?).self) { group in
            // Seed the group with initial tasks
            let seedCount = min(maxConcurrency, total)
            while index < seedCount {
                let url = audioFiles[index]
                index += 1
                let path = url.path
                group.addTask { [self] in
                    logger.info("Reading: \(url.lastPathComponent)")
                    do {
                        let track = try extractMetadata(from: path)
                        return (track, nil, nil)
                    } catch {
                        logger.error("Error reading \(url.lastPathComponent): \(error.localizedDescription)")
                        return (nil, path, error.localizedDescription)
                    }
                }
            }
            // As each task finishes, collect the result and add the next task
            for try await (track, errorPath, errorReason) in group {
                completed += 1
                onProgress?(completed, total)
                if let track = track {
                    tracksToInsert.append(track)
                    logger.info("[\(completed)/\(total)] Done: \(track.artist) — \(track.title)")
                } else if let errorPath = errorPath {
                    errors.append(errorPath)
                    let reason = errorReason ?? "unknown error"
                    logger.error("[\(completed)/\(total)] Failed (\(reason))")
                }
                if index < total {
                    let url = audioFiles[index]
                    index += 1
                    let path = url.path
                    group.addTask { [self] in
                        logger.info("Reading: \(url.lastPathComponent)")
                        do {
                            let track = try extractMetadata(from: path)
                            return (track, nil, nil)
                        } catch {
                            logger.error("Error reading \(url.lastPathComponent): \(error.localizedDescription)")
                            return (nil, path, error.localizedDescription)
                        }
                    }
                }
            }
        }

        // Batch insert all new/changed tracks in a single transaction
        logger.info("Saving \(tracksToInsert.count) tracks to database...")
        try database.insertOrUpdateSongs(tracksToInsert)
        erroredFiles = errors

        logger.info("Scan complete — \(tracksToInsert.count) saved, \(errors.count) failed")
        for path in erroredFiles {
            logger.warning("Failed: \(path)")
        }
    }

    private func collectFilesToProcess(existingPaths: [String: Date]) -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: musicDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            logger.warning("Could not create enumerator for \(self.musicDirectory.path)")
            return []
        }

        var audioFiles: [URL] = []
        var skipped = 0
        for case let fileURL as URL in enumerator {
            guard MusicExtension(rawValue: fileURL.pathExtension.lowercased()) != nil else {
                continue
            }
            let modDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            if let existing = existingPaths[fileURL.path], existing >= modDate {
                skipped += 1
                continue
            }
            audioFiles.append(fileURL)
        }
        logger.info("Enumeration complete — \(audioFiles.count + skipped) audio files found, \(skipped) unchanged")
        return audioFiles
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
            "-probesize", "100000",  // Read at most 100KB to probe the container (default is 5MB)
            "-show_format",
            "-show_streams",         // OGG/Vorbis stores tags at stream level, not format level
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
              let format = json["format"] as? [String: Any] else {
            throw TrackError.noMetadata(path)
        }

        // Tags may be at format level (MP3, M4A) or stream level (OGG/Vorbis, some FLAC)
        let formatTags = format["tags"] as? [String: Any]
        let streamTags = (json["streams"] as? [[String: Any]])?.first(where: {
            ($0["codec_type"] as? String) == "audio"
        })?["tags"] as? [String: Any]
        guard let tags = formatTags ?? streamTags else {
            throw TrackError.noMetadata(path)
        }

        return buildTrack(tags: tags, format: format, path: path)
    }

    func buildTrack(tags: [String: Any], format: [String: Any], path: String) -> Track {
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
        let resolvedLyricType: LyricType?
        if let lyrics = lyrics {
            let isSynced = lyrics.range(of: #"\[\d{2}:\d{2}\.\d{2}\]"#, options: .regularExpression) != nil
            resolvedLyricType = isSynced ? .synced : .plain
        } else {
            resolvedLyricType = nil
        }

        return Track(
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
            lyricType: resolvedLyricType,
            lastModified: Date()
        )
    }

    func loadLyrics(for audioPath: String, extension ext: String) -> String? {
        let url = URL(fileURLWithPath: audioPath)
        let lyricsPath = url.deletingPathExtension().appendingPathExtension(ext).path
        return try? String(contentsOfFile: lyricsPath, encoding: .utf8)
    }
}
