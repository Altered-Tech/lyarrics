enum TrackError: Error {
    case parseFailed(String, String)
    case titleNotFound(String)
    case albumNotFound(String)
    case artistNotFound(String)
    case noMetadata(String)
    case executableNotFound(String)
    case fileNotFound(String)
}