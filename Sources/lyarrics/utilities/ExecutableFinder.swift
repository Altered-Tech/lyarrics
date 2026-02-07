import Foundation

internal func findExecutable(_ name: String) -> URL? {
    guard let pathEnv = ProcessInfo.processInfo.environment["PATH"] else {
        return nil
    }
    
    let paths = pathEnv.split(separator: ":").map(String.init)
    let fileManager = FileManager.default
    
    for dir in paths {
        let fullPath = "\(dir)/\(name)"
        if fileManager.isExecutableFile(atPath: fullPath) {
            return URL(fileURLWithPath: fullPath)
        }
    }
    return nil
}
