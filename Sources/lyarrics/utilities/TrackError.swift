import Foundation

enum TrackError: Error {
    case parseFailed(String, String)
    case titleNotFound(String)
    case albumNotFound(String)
    case artistNotFound(String)
    case noMetadata(String)
    case executableNotFound(String)
    case fileNotFound(String)
    case pathNotFound(String)
}

extension TrackError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .parseFailed(let path, let detail):
            return "Parse failed for '\(path)': \(detail)"
        case .titleNotFound(let path):
            return "Title not found in metadata: \(path)"
        case .albumNotFound(let path):
            return "Album not found in metadata: \(path)"
        case .artistNotFound(let path):
            return "Artist not found in metadata: \(path)"
        case .noMetadata(let path):
            return "No tags found in file (ffprobe returned no metadata): \(path)"
        case .executableNotFound(let name):
            return "Required executable not found in PATH: \(name)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .pathNotFound(let path):
            return "Directory not found: \(path)"
        }
    }
}