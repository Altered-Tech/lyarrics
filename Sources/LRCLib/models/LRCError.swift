
public enum LRCError: Error {
    case notFound(_ message: String? = nil)
    case undocumented(_ statusCode: Int, _ message: String? = nil)
    case decodingError(_ error: Error? = nil)
}