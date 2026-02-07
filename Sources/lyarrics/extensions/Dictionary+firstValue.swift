extension Dictionary where Key == String, Value == Any {
    func firstValue(forKeys keys: [String]) -> String? {
        for key in keys {
            if let value = self[key] as? String {
                return value
            }
        }
        return nil
    }
}