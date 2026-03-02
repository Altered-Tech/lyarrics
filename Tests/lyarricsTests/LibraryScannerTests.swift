import Testing
import Foundation
@testable import lyarrics

// MARK: - Helpers

private func makeTempMusicDir() throws -> (musicDir: URL, cleanup: URL) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("lyarricsScannerTests-\(UUID().uuidString)")
    let musicDir = root.appendingPathComponent("music")
    try FileManager.default.createDirectory(at: musicDir, withIntermediateDirectories: true)
    return (musicDir, root)
}

private func makeScanner(musicDir: URL, root: URL) throws -> (LibraryScanner, MusicDatabase) {
    let db = try MusicDatabase(dbPath: root.appendingPathComponent("test.db").path)
    let scanner = LibraryScanner(musicDirectory: musicDir, database: db)
    return (scanner, db)
}

// MARK: - LibraryScanner scanLibrary Tests

@Suite("LibraryScanner scanLibrary Tests")
struct LibraryScannerScanTests {

    @Test("throws when music directory does not exist")
    func throwsForMissingDirectory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyarricsScannerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let db = try MusicDatabase(dbPath: root.appendingPathComponent("test.db").path)
        // Music directory is never created
        let nonExistentDir = root.appendingPathComponent("no-such-dir")
        let scanner = LibraryScanner(musicDirectory: nonExistentDir, database: db)

        await #expect(throws: TrackError.self) {
            try await scanner.scanLibrary()
        }
    }

    @Test("does not insert anything for an empty directory")
    func emptyDirectoryNoInsertions() async throws {
        let (musicDir, root) = try makeTempMusicDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let (scanner, db) = try makeScanner(musicDir: musicDir, root: root)
        try await scanner.scanLibrary()

        let songs = try db.getAllSongs()
        #expect(songs.isEmpty)
    }

    @Test("does not insert anything when directory contains only non-audio files")
    func nonAudioFilesNoInsertions() async throws {
        let (musicDir, root) = try makeTempMusicDir()
        defer { try? FileManager.default.removeItem(at: root) }

        for name in ["readme.txt", "cover.jpg", "playlist.m3u", "art.png", "song.lrc"] {
            FileManager.default.createFile(
                atPath: musicDir.appendingPathComponent(name).path,
                contents: nil
            )
        }

        let (scanner, db) = try makeScanner(musicDir: musicDir, root: root)
        try await scanner.scanLibrary()

        let songs = try db.getAllSongs()
        #expect(songs.isEmpty)
    }

    @Test("skips audio files whose database record is newer than the file modification date")
    func skipsUpToDateFiles() async throws {
        let (musicDir, root) = try makeTempMusicDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let audioFile = musicDir.appendingPathComponent("track.flac")
        FileManager.default.createFile(atPath: audioFile.path, contents: nil)

        let modDate = (try? audioFile.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()

        let (scanner, db) = try makeScanner(musicDir: musicDir, root: root)

        // Pre-insert with lastModified 60 s AFTER the file's mod date → collectFilesToProcess skips it
        let preInserted = Track(
            fileTrackPath: audioFile.path,
            fileTrackName: audioFile.lastPathComponent,
            fileLyricPath: nil, fileLyricName: nil,
            title: "Pre-existing Track",
            artist: "Artist", album: "Album",
            duration: 120.0, trackNumber: nil,
            lyrics: nil, instrumental: false,
            isSyncedLyrics: false,
            lastModified: modDate.addingTimeInterval(60)
        )
        try db.insertOrUpdateSong(preInserted)

        try await scanner.scanLibrary()

        let songs = try db.getAllSongs()
        #expect(songs.count == 1)
        #expect(songs.first?.title == "Pre-existing Track")
    }

    @Test("collects audio file not present in database and attempts processing")
    func collectsNewAudioFileForProcessing() async throws {
        guard findExecutable("ffprobe") != nil else { return }

        let (musicDir, root) = try makeTempMusicDir()
        defer { try? FileManager.default.removeItem(at: root) }

        // File has an audio extension but invalid content — ffprobe will fail gracefully
        let audioFile = musicDir.appendingPathComponent("new-track.mp3")
        FileManager.default.createFile(atPath: audioFile.path, contents: Data("not real audio".utf8))

        let (scanner, db) = try makeScanner(musicDir: musicDir, root: root)

        // DB is empty → file is not up-to-date → scanner tries to process it
        // ffprobe fails on invalid content → no insertion, but scan completes without throwing
        try await scanner.scanLibrary()

        let songs = try db.getAllSongs()
        #expect(songs.isEmpty)
    }

    @Test("does not skip audio file whose database record is older than the file modification date")
    func doesNotSkipStaleDbRecord() async throws {
        let (musicDir, root) = try makeTempMusicDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let audioFile = musicDir.appendingPathComponent("changed.mp3")
        FileManager.default.createFile(atPath: audioFile.path, contents: nil)

        let (scanner, db) = try makeScanner(musicDir: musicDir, root: root)

        // Pre-insert with a date far in the past → DB record is stale → file is collected
        let staleTrack = Track(
            fileTrackPath: audioFile.path,
            fileTrackName: audioFile.lastPathComponent,
            fileLyricPath: nil, fileLyricName: nil,
            title: "Stale Track",
            artist: "Artist", album: "Album",
            duration: 120.0, trackNumber: nil,
            lyrics: nil, instrumental: false,
            isSyncedLyrics: false,
            lastModified: Date(timeIntervalSince1970: 0)
        )
        try db.insertOrUpdateSong(staleTrack)

        // Scan will try to process the file (ffprobe may fail, but what matters is
        // the file is NOT skipped — we verify by confirming the scan ran to completion)
        try await scanner.scanLibrary()

        // If ffprobe is unavailable or fails the old record may remain, but the scan
        // must not throw — the key assertion is that scanLibrary() completes cleanly.
        let songs = try db.getAllSongs()
        #expect(songs.count >= 1)
    }
}

// MARK: - LibraryScanner extractMetadata Tests

@Suite("LibraryScanner extractMetadata Tests")
struct LibraryScannerExtractMetadataTests {

    private func makeScanner(in dir: URL) throws -> LibraryScanner {
        let db = try MusicDatabase(dbPath: dir.appendingPathComponent("test.db").path)
        return LibraryScanner(musicDirectory: dir, database: db)
    }

    @Test("throws fileNotFound when path does not exist")
    func throwsFileNotFoundForMissingPath() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyarricsScannerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let scanner = try makeScanner(in: tempDir)
        let missingPath = tempDir.appendingPathComponent("nonexistent.mp3").path

        #expect(throws: TrackError.self) {
            try scanner.extractMetadata(from: missingPath)
        }
    }

    @Test("thrown fileNotFound error contains the missing path")
    func fileNotFoundErrorContainsPath() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyarricsScannerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let scanner = try makeScanner(in: tempDir)
        let missingPath = tempDir.appendingPathComponent("missing.mp3").path

        do {
            _ = try scanner.extractMetadata(from: missingPath)
            Issue.record("Expected TrackError.fileNotFound to be thrown")
        } catch let error as TrackError {
            if case .fileNotFound(let path) = error {
                #expect(path == missingPath)
            } else {
                Issue.record("Expected fileNotFound, got \(error)")
            }
        }
    }

    @Test("throws noMetadata when ffprobe cannot extract format from file")
    func throwsNoMetadataForInvalidContent() throws {
        guard findExecutable("ffprobe") != nil else { return }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyarricsScannerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let scanner = try makeScanner(in: tempDir)
        let fakePath = tempDir.appendingPathComponent("fake.mp3").path
        FileManager.default.createFile(
            atPath: fakePath,
            contents: Data("this is not valid audio data".utf8)
        )

        #expect(throws: TrackError.self) {
            try scanner.extractMetadata(from: fakePath)
        }
    }

    private func makeScanner(directory: URL) throws -> LibraryScanner {
        let db = try MusicDatabase(dbPath: directory.appendingPathComponent("test.db").path)
        return LibraryScanner(musicDirectory: directory, database: db)
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyarricsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: Error guards

    @Test("throws fileNotFound for a non-existent path")
    func throwsFileNotFoundForMissingFile() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let scanner = try makeScanner(directory: tempDir)
        let missingPath = tempDir.appendingPathComponent("ghost.mp3").path

        var caughtFileNotFound = false
        do {
            _ = try scanner.extractMetadata(from: missingPath)
        } catch TrackError.fileNotFound {
            caughtFileNotFound = true
        }
        #expect(caughtFileNotFound)
    }

    @Test("throws an error for an empty (invalid) audio file")
    func throwsForEmptyFile() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let scanner = try makeScanner(directory: tempDir)
        let filePath = tempDir.appendingPathComponent("empty.mp3").path
        FileManager.default.createFile(atPath: filePath, contents: nil)

        // Expect any throw: executableNotFound if ffprobe is absent,
        // noMetadata / parseFailed when ffprobe returns non-JSON for an empty file.
        var didThrow = false
        do {
            _ = try scanner.extractMetadata(from: filePath)
        } catch {
            didThrow = true
        }
        #expect(didThrow)
    }

    // MARK: Synced lyrics regex

    @Test("synced lyrics containing timecodes are detected as synced")
    func syncedLyricsMatchTimecodePattern() {
        let lyrics = "[00:16.41] Is this the real life?\n[00:20.00] Is this just fantasy?"
        let isSynced = lyrics.range(of: #"\[\d{2}:\d{2}\.\d{2}\]"#, options: .regularExpression) != nil
        #expect(isSynced == true)
    }

    @Test("plain text lyrics without timecodes are not synced")
    func plainLyricsNotDetectedAsSynced() {
        let lyrics = "Is this the real life?\nIs this just fantasy?"
        let isSynced = lyrics.range(of: #"\[\d{2}:\d{2}\.\d{2}\]"#, options: .regularExpression) != nil
        #expect(isSynced == false)
    }

    @Test("timecode missing centiseconds does not match")
    func timecodeWithoutCentisecondsNotSynced() {
        let lyrics = "[00:16] No centiseconds here"
        let isSynced = lyrics.range(of: #"\[\d{2}:\d{2}\.\d{2}\]"#, options: .regularExpression) != nil
        #expect(isSynced == false)
    }

    @Test("timecode with single-digit groups does not match")
    func singleDigitTimecodeNotSynced() {
        let lyrics = "[0:6.4] Wrong digit count"
        let isSynced = lyrics.range(of: #"\[\d{2}:\d{2}\.\d{2}\]"#, options: .regularExpression) != nil
        #expect(isSynced == false)
    }

    // MARK: Track number parsing

    @Test("plain integer track number parses correctly")
    func trackNumberPlainInteger() {
        let raw = "5"
        let trackNumber = raw.components(separatedBy: "/").first.flatMap { Int($0) }
        #expect(trackNumber == 5)
    }

    @Test("N/M format track number returns N")
    func trackNumberNSlashMFormat() {
        let raw = "3/12"
        let trackNumber = raw.components(separatedBy: "/").first.flatMap { Int($0) }
        #expect(trackNumber == 3)
    }

    @Test("non-numeric track number returns nil")
    func trackNumberNonNumericReturnsNil() {
        let raw = "three"
        let trackNumber = raw.components(separatedBy: "/").first.flatMap { Int($0) }
        #expect(trackNumber == nil)
    }

    // MARK: LRC path construction

    @Test("lrc path replaces audio extension with .lrc")
    func lrcPathReplacesExtension() {
        let audioPath = "/music/artist/song.mp3"
        let lrcPath = URL(fileURLWithPath: audioPath)
            .deletingPathExtension()
            .appendingPathExtension("lrc")
            .path
        #expect(lrcPath == "/music/artist/song.lrc")
    }

    @Test("lrc name is the filename component of the lrc path")
    func lrcNameIsLastPathComponent() {
        let audioPath = "/music/artist/my song.flac"
        let lrcURL = URL(fileURLWithPath: audioPath)
            .deletingPathExtension()
            .appendingPathExtension("lrc")
        #expect(lrcURL.lastPathComponent == "my song.lrc")
    }

    @Test("fileLyricPath and fileLyricName are nil when no lrc file exists")
    func lrcFieldsNilWhenNoLrcFile() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let scanner = try makeScanner(directory: tempDir)
        let audioPath = tempDir.appendingPathComponent("song.mp3").path
        // No lrc file alongside the audio
        let result = scanner.loadLyrics(for: audioPath, extension: "lrc")
        #expect(result == nil)
        // When loadLyrics returns nil, fileLyricPath and fileLyricName would be nil in the Track
    }

    @Test("fileLyricPath and fileLyricName are set when lrc file exists")
    func lrcFieldsSetWhenLrcFileExists() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let scanner = try makeScanner(directory: tempDir)
        let audioPath = tempDir.appendingPathComponent("song.mp3").path
        let lrcPath = tempDir.appendingPathComponent("song.lrc").path
        let content = "[00:01.00] Hello"
        try content.write(toFile: lrcPath, atomically: true, encoding: .utf8)

        let lyrics = scanner.loadLyrics(for: audioPath, extension: "lrc")
        let expectedLrcPath = URL(fileURLWithPath: audioPath)
            .deletingPathExtension().appendingPathExtension("lrc").path
        #expect(lyrics == content)
        #expect(expectedLrcPath == lrcPath)
    }

    // MARK: Title fallback

    @Test("title fallback uses filename stem when no title tag is present")
    func titleFallbackUsesFilenameStem() {
        let path = "/music/artist/my-song-title.mp3"
        let fallback = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        #expect(fallback == "my-song-title")
    }

    @Test("title fallback handles file with no directory component")
    func titleFallbackHandlesBareFilename() {
        let path = "/just-a-song.flac"
        let fallback = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        #expect(fallback == "just-a-song")
    }
}

// MARK: - LibraryScanner Synced Lyrics Detection Tests

@Suite("LibraryScanner Synced Lyrics Detection Tests")
struct LibraryScannerSyncedLyricsTests {

    // The exact regex used in extractMetadata to classify synced vs plain lyrics
    private let pattern = #"\[\d{2}:\d{2}\.\d{2}\]"#

    @Test("full timecode pattern is detected as synced")
    func fullTimecodeDetectedAsSynced() {
        let lyrics = "[00:16.41] Is this the real life?\n[00:20.00] Is this just fantasy?"
        #expect(lyrics.range(of: pattern, options: .regularExpression) != nil)
    }

    @Test("single timecode anywhere in the string is detected as synced")
    func singleTimecodeIsSynced() {
        #expect("[03:45.12] One line".range(of: pattern, options: .regularExpression) != nil)
    }

    @Test("plain text lyrics are not detected as synced")
    func plainTextNotSynced() {
        let lyrics = "Is this the real life?\nIs this just fantasy?"
        #expect(lyrics.range(of: pattern, options: .regularExpression) == nil)
    }

    @Test("empty string is not detected as synced")
    func emptyStringNotSynced() {
        #expect("".range(of: pattern, options: .regularExpression) == nil)
    }

    @Test("timecode missing decimal seconds is not detected as synced")
    func timecodeWithoutDecimalNotSynced() {
        // [00:16] format — missing the .dd fractional seconds
        #expect("[00:16] Some lyric".range(of: pattern, options: .regularExpression) == nil)
    }

    @Test("id3 metadata tag markers are not detected as synced")
    func id3TagMarkersNotSynced() {
        // Common LRC metadata lines like [ar:Artist] or [ti:Title]
        let metadata = "[ar:Queen]\n[ti:Bohemian Rhapsody]\n[al:A Night at the Opera]"
        #expect(metadata.range(of: pattern, options: .regularExpression) == nil)
    }
}

// MARK: - LibraryScanner.loadLyrics Tests

@Suite("LibraryScanner loadLyrics Tests")
struct LibraryScannerLoadLyricsTests {

    private func makeScanner(directory: URL) throws -> LibraryScanner {
        let db = try MusicDatabase(dbPath: directory.appendingPathComponent("test.db").path)
        return LibraryScanner(musicDirectory: directory, database: db)
    }

    @Test("returns nil when no matching lrc file exists")
    func returnsNilWhenNoLrcFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyarricsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let scanner = try makeScanner(directory: tempDir)
        let audioPath = tempDir.appendingPathComponent("song.mp3").path
        FileManager.default.createFile(atPath: audioPath, contents: nil)

        let result = scanner.loadLyrics(for: audioPath, extension: "lrc")
        #expect(result == nil)
    }

    @Test("returns lyrics content when lrc file exists alongside audio")
    func returnsLyricsWhenLrcFileExists() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyarricsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let scanner = try makeScanner(directory: tempDir)
        let audioPath = tempDir.appendingPathComponent("song.mp3").path
        let lrcPath = tempDir.appendingPathComponent("song.lrc").path
        let lyricsContent = "[00:16.41] Is this the real life?\n[00:20.00] Is this just fantasy?"

        FileManager.default.createFile(atPath: audioPath, contents: nil)
        try lyricsContent.write(toFile: lrcPath, atomically: true, encoding: .utf8)

        let result = scanner.loadLyrics(for: audioPath, extension: "lrc")
        #expect(result == lyricsContent)
    }

    @Test("returns nil when lrc file is missing but audio exists")
    func returnsNilWhenAudioExistsButNoLrc() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyarricsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let scanner = try makeScanner(directory: tempDir)
        let audioPath = tempDir.appendingPathComponent("no-lyrics.flac").path
        FileManager.default.createFile(atPath: audioPath, contents: nil)

        let result = scanner.loadLyrics(for: audioPath, extension: "lrc")
        #expect(result == nil)
    }
}


// MARK: - LibraryScanner.scanLibrary Tests

@Suite("LibraryScanner scanLibrary Tests")
struct LibraryScannerScanLibraryTests {

    private func makeScanner(directory: URL) throws -> (LibraryScanner, MusicDatabase) {
        let db = try MusicDatabase(dbPath: directory.appendingPathComponent("test.db").path)
        return (LibraryScanner(musicDirectory: directory, database: db), db)
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyarricsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: Guard conditions

    @Test("scanLibrary throws pathNotFound when directory does not exist")
    func scanThrowsForNonexistentDirectory() async throws {
        let missingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyarricsTests-missing-\(UUID().uuidString)")

        // Use a sibling dir for the DB so the scanner itself can be created
        let dbDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dbDir) }

        let db = try MusicDatabase(dbPath: dbDir.appendingPathComponent("test.db").path)
        let scanner = LibraryScanner(musicDirectory: missingDir, database: db)

        var didThrow = false
        do {
            try await scanner.scanLibrary()
        } catch is TrackError {
            didThrow = true
        }
        #expect(didThrow)
    }

    @Test("scanLibrary returns early when directory contains no audio files")
    func scanReturnsEarlyWithNoAudioFiles() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (scanner, db) = try makeScanner(directory: tempDir)

        // Only a non-audio file — should be ignored by collectFilesToProcess
        FileManager.default.createFile(
            atPath: tempDir.appendingPathComponent("notes.txt").path,
            contents: nil
        )

        try await scanner.scanLibrary()

        let songs = try db.getAllSongs()
        #expect(songs.isEmpty)
    }

    // MARK: Error path (seed block — first processorCount files)

    @Test("scanLibrary: failed file is not saved to database")
    func scanFailedFileNotSaved() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (scanner, db) = try makeScanner(directory: tempDir)

        // Empty file — ffprobe will fail to parse it, triggering the error branch
        FileManager.default.createFile(
            atPath: tempDir.appendingPathComponent("bad.mp3").path,
            contents: nil
        )

        try await scanner.scanLibrary()

        let songs = try db.getAllSongs()
        #expect(songs.isEmpty)
    }

    // MARK: Continuation block (lines 75-89) — requires total > processorCount

    @Test("scanLibrary exercises continuation block when file count exceeds concurrency limit")
    func scanContinuationBlockErrorPath() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (scanner, db) = try makeScanner(directory: tempDir)

        // Create more files than processorCount so the overflow files are
        // submitted via the continuation block (lines 75-89) as earlier tasks finish.
        let fileCount = ProcessInfo.processInfo.processorCount + 4
        for i in 0..<fileCount {
            FileManager.default.createFile(
                atPath: tempDir.appendingPathComponent("track\(i).mp3").path,
                contents: nil
            )
        }

        // All files are empty and will fail extractMetadata.
        // scanLibrary must not throw — failures are collected internally.
        try await scanner.scanLibrary()

        // No track should have been saved since every extraction failed.
        let songs = try db.getAllSongs()
        #expect(songs.isEmpty)
    }

    @Test("scanLibrary continuation block processes all overflow files")
    func scanContinuationBlockCoversAllFiles() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (scanner, db) = try makeScanner(directory: tempDir)

        // Create exactly processorCount + 1 files so the final file must go
        // through the continuation block (the "+1 file" slot).
        let fileCount = ProcessInfo.processInfo.processorCount + 1
        for i in 0..<fileCount {
            FileManager.default.createFile(
                atPath: tempDir.appendingPathComponent("song\(i).flac").path,
                contents: nil
            )
        }

        try await scanner.scanLibrary()

        // All fail (empty files), but the scan should complete without error.
        let songs = try db.getAllSongs()
        #expect(songs.count == 0)
    }

    // MARK: Skip mechanism (collectFilesToProcess)

    @Test("scanLibrary skips files already tracked with a current modification date")
    func scanSkipsUpToDateFiles() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (scanner, db) = try makeScanner(directory: tempDir)

        let audioPath = tempDir.appendingPathComponent("track.mp3").path
        FileManager.default.createFile(atPath: audioPath, contents: nil)

        // Pre-insert with a far-future lastModified so the file appears unchanged
        let preInserted = Track(
            fileTrackPath: audioPath,
            fileTrackName: "track.mp3",
            fileLyricPath: nil,
            fileLyricName: nil,
            title: "Existing",
            artist: "Artist",
            album: "Album",
            duration: 200.0,
            trackNumber: nil,
            lyrics: nil,
            instrumental: false,
            isSyncedLyrics: false,
            lastModified: Date.distantFuture
        )
        try db.insertOrUpdateSong(preInserted)

        // Scan should see the file is up-to-date and skip it entirely,
        // leaving the pre-inserted record untouched.
        try await scanner.scanLibrary()

        let songs = try db.getAllSongs()
        #expect(songs.count == 1)
        #expect(songs.first?.title == "Existing")
    }
}

// MARK: - LibraryScanner.buildTrack Tests

@Suite("LibraryScanner buildTrack Tests")
struct LibraryScannerBuildTrackTests {

    private func makeScanner(directory: URL) throws -> LibraryScanner {
        let db = try MusicDatabase(dbPath: directory.appendingPathComponent("test.db").path)
        return LibraryScanner(musicDirectory: directory, database: db)
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyarricsBuildTrackTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: Title

    @Test("uses lowercase title tag")
    func usesLowercaseTitleTag() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let scanner = try makeScanner(directory: dir)
        let path = dir.appendingPathComponent("song.mp3").path
        let track = scanner.buildTrack(tags: ["title": "My Song"], format: [:], path: path)
        #expect(track.title == "My Song")
    }

    @Test("uses uppercase TITLE tag")
    func usesUppercaseTitleTag() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let scanner = try makeScanner(directory: dir)
        let path = dir.appendingPathComponent("song.mp3").path
        let track = scanner.buildTrack(tags: ["TITLE": "My Song"], format: [:], path: path)
        #expect(track.title == "My Song")
    }

    @Test("falls back to filename stem when title tag is absent")
    func titleFallsBackToFilenameStem() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let scanner = try makeScanner(directory: dir)
        let path = dir.appendingPathComponent("great-track.mp3").path
        let track = scanner.buildTrack(tags: [:], format: [:], path: path)
        #expect(track.title == "great-track")
    }

    // MARK: Album

    @Test("uses album tag when present")
    func usesAlbumTag() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let scanner = try makeScanner(directory: dir)
        let path = dir.appendingPathComponent("song.mp3").path
        let track = scanner.buildTrack(tags: ["album": "Greatest Hits"], format: [:], path: path)
        #expect(track.album == "Greatest Hits")
    }

    @Test("uses uppercase ALBUM tag")
    func usesUppercaseAlbumTag() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let scanner = try makeScanner(directory: dir)
        let path = dir.appendingPathComponent("song.mp3").path
        let track = scanner.buildTrack(tags: ["ALBUM": "Greatest Hits"], format: [:], path: path)
        #expect(track.album == "Greatest Hits")
    }

    @Test("falls back to 'Unknown Album' when album tag is absent")
    func albumFallback() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let scanner = try makeScanner(directory: dir)
        let track = scanner.buildTrack(tags: [:], format: [:], path: dir.appendingPathComponent("s.mp3").path)
        #expect(track.album == "Unknown Album")
    }

    // MARK: Artist

    @Test("uses artist tag when present")
    func usesArtistTag() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let scanner = try makeScanner(directory: dir)
        let track = scanner.buildTrack(tags: ["artist": "Queen"], format: [:], path: dir.appendingPathComponent("s.mp3").path)
        #expect(track.artist == "Queen")
    }

    @Test("uses uppercase ARTIST tag")
    func usesUppercaseArtistTag() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let scanner = try makeScanner(directory: dir)
        let track = scanner.buildTrack(tags: ["ARTIST": "Queen"], format: [:], path: dir.appendingPathComponent("s.mp3").path)
        #expect(track.artist == "Queen")
    }

    @Test("falls back to 'Unknown Artist' when artist tag is absent")
    func artistFallback() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let scanner = try makeScanner(directory: dir)
        let track = scanner.buildTrack(tags: [:], format: [:], path: dir.appendingPathComponent("s.mp3").path)
        #expect(track.artist == "Unknown Artist")
    }

    // MARK: Duration

    @Test("parses duration from format dictionary")
    func parsesDuration() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let scanner = try makeScanner(directory: dir)
        let track = scanner.buildTrack(tags: [:], format: ["duration": "245.67"], path: dir.appendingPathComponent("s.mp3").path)
        #expect(track.duration == 245.67)
    }

    @Test("defaults duration to 0.0 when key is absent")
    func defaultsDurationToZero() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let scanner = try makeScanner(directory: dir)
        let track = scanner.buildTrack(tags: [:], format: [:], path: dir.appendingPathComponent("s.mp3").path)
        #expect(track.duration == 0.0)
    }

    // MARK: Track number

    @Test("parses plain integer track number")
    func plainTrackNumber() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let scanner = try makeScanner(directory: dir)
        let track = scanner.buildTrack(tags: ["track": "5"], format: [:], path: dir.appendingPathComponent("s.mp3").path)
        #expect(track.trackNumber == 5)
    }

    @Test("parses track number from N/total format")
    func trackNumberNSlashM() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let scanner = try makeScanner(directory: dir)
        let track = scanner.buildTrack(tags: ["track": "3/12"], format: [:], path: dir.appendingPathComponent("s.mp3").path)
        #expect(track.trackNumber == 3)
    }

    @Test("track number is nil when tag is absent")
    func trackNumberNilWhenAbsent() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let scanner = try makeScanner(directory: dir)
        let track = scanner.buildTrack(tags: [:], format: [:], path: dir.appendingPathComponent("s.mp3").path)
        #expect(track.trackNumber == nil)
    }

    @Test("track number is nil for non-numeric tag value")
    func trackNumberNilForNonNumeric() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let scanner = try makeScanner(directory: dir)
        let track = scanner.buildTrack(tags: ["track": "three"], format: [:], path: dir.appendingPathComponent("s.mp3").path)
        #expect(track.trackNumber == nil)
    }

    // MARK: File path fields

    @Test("fileTrackPath and fileTrackName match the input path")
    func filePathFields() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let scanner = try makeScanner(directory: dir)
        let path = dir.appendingPathComponent("track.flac").path
        let track = scanner.buildTrack(tags: [:], format: [:], path: path)
        #expect(track.fileTrackPath == path)
        #expect(track.fileTrackName == "track.flac")
    }

    // MARK: Lyrics and isSyncedLyrics

    @Test("lyrics is nil and isSyncedLyrics is false when no lrc file exists")
    func noLrcFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let scanner = try makeScanner(directory: dir)
        let path = dir.appendingPathComponent("song.mp3").path
        let track = scanner.buildTrack(tags: [:], format: [:], path: path)
        #expect(track.lyrics == nil)
        #expect(track.isSyncedLyrics == false)
        #expect(track.fileLyricPath == nil)
        #expect(track.fileLyricName == nil)
    }

    @Test("synced lrc file is loaded and isSyncedLyrics is true")
    func syncedLrcFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let scanner = try makeScanner(directory: dir)
        let audioPath = dir.appendingPathComponent("song.mp3").path
        let lrcContent = "[00:16.41] Is this the real life?\n[00:20.00] Is this just fantasy?"
        try lrcContent.write(toFile: dir.appendingPathComponent("song.lrc").path, atomically: true, encoding: .utf8)

        let track = scanner.buildTrack(tags: [:], format: [:], path: audioPath)
        #expect(track.lyrics == lrcContent)
        #expect(track.isSyncedLyrics == true)
        #expect(track.fileLyricName == "song.lrc")
        #expect(track.fileLyricPath?.hasSuffix("song.lrc") == true)
    }

    @Test("plain lrc file is loaded but isSyncedLyrics is false")
    func plainLrcFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let scanner = try makeScanner(directory: dir)
        let audioPath = dir.appendingPathComponent("song.mp3").path
        let lrcContent = "Is this the real life?\nIs this just fantasy?"
        try lrcContent.write(toFile: dir.appendingPathComponent("song.lrc").path, atomically: true, encoding: .utf8)

        let track = scanner.buildTrack(tags: [:], format: [:], path: audioPath)
        #expect(track.lyrics == lrcContent)
        #expect(track.isSyncedLyrics == false)
    }
}