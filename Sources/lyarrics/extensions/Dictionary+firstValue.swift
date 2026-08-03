extension Dictionary where Key == String, Value == Any {
    /// Looks up each key in order, trying an exact match first, then falling back to a
    /// case-insensitive match against the dictionary's actual keys. This catches casings
    /// (e.g. `Title`) that weren't explicitly listed in `keys`, without needing every
    /// caller to enumerate every casing variant a tagger might use.
    func firstValue(forKeys keys: [String]) -> String? {
        for key in keys {
            if let value = self[key] as? String {
                return value
            }
            // Sorted so the result is deterministic even if multiple keys collide
            // case-insensitively (e.g. malformed tags with both `Title` and `TITLE`) —
            // Dictionary iteration order is unspecified and not stable across runs.
            let lowercasedKey = key.lowercased()
            let candidateKey = self.keys
                .filter { $0.lowercased() == lowercasedKey }
                .sorted()
                .first
            if let candidateKey, let value = self[candidateKey] as? String {
                return value
            }
        }
        return nil
    }
}