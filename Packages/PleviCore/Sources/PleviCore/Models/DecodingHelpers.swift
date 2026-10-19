
import Foundation

extension KeyedDecodingContainer {
    /// Decodes an `Int` that may have arrived as a JSON number or a numeric string.
    /// Returns `nil` (never throws) if the key is missing or unparsable.
    func decodeFlexibleIntIfPresent(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        if let string = try? decodeIfPresent(String.self, forKey: key) { return Int(string) }
        return nil
    }

    /// Decodes a `Double` that may have arrived as a JSON number or a numeric string.
    func decodeFlexibleDoubleIfPresent(forKey key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let string = try? decodeIfPresent(String.self, forKey: key) { return Double(string) }
        return nil
    }

    /// Decodes a `Bool` that may have arrived as a JSON bool, a 0/1 number, or "true"/"false".
    func decodeFlexibleBoolIfPresent(forKey key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value != 0 }
        if let string = try? decodeIfPresent(String.self, forKey: key)?.lowercased() {
            if string == "true" || string == "1" { return true }
            if string == "false" || string == "0" { return false }
        }
        return nil
    }

    /// Decodes a `String` that may have arrived as a JSON string or a number.
    func decodeFlexibleStringIfPresent(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return String(value) }
        return nil
    }
}
