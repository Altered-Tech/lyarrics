
public struct Track {
    public var title: String

    public init(_ title: String) {
        self.title = title
    }

    internal var query: Components.Parameters.TrackName {
        title
    }
}