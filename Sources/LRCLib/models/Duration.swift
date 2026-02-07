
public struct Duration {
    public let seconds: Int

    public init(_ seconds: Int) {
        self.seconds = seconds
    }

    internal var query: Components.Parameters.Duration {
        seconds
    }
}