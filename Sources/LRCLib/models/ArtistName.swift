
public struct Artist {
    public var name: String

    public init(_ name: String) {
        self.name = name
    }

    internal var query: Components.Parameters.ArtistName {
        name
    }
}