import Foundation

/// Fractional indexing for stable ordering of blocks and notes.
///
/// Keys are non-empty base-36 strings (`0-9a-z`) that never end in "0". Any two
/// distinct keys have a key strictly between them, so moving an item only
/// rewrites that item's key. Based on the well-known algorithm used by
/// rocicorp/fractional-indexing (fractional part only).
public enum Rank {
    public enum Error: Swift.Error, Equatable {
        case invalidKey(String)
        case outOfOrder(String, String)
    }

    static let digits: [Character] = Array("0123456789abcdefghijklmnopqrstuvwxyz")
    static let base = digits.count

    /// A key strictly between `lower` and `upper`. `nil` means unbounded.
    public static func between(_ lower: String?, _ upper: String?) throws -> String {
        if let lower { try validate(lower) }
        if let upper { try validate(upper) }
        if let lower, let upper, lower >= upper {
            throw Error.outOfOrder(lower, upper)
        }
        return midpoint(Array(lower ?? ""), upper.map(Array.init))
    }

    /// The key for the first item in an empty list.
    public static var initial: String { midpoint([], nil) }

    /// `count` keys, evenly spaced and ascending; used to normalize ranks when
    /// keys have grown long after many insertions.
    public static func evenlySpaced(_ count: Int) -> [String] {
        guard count > 0 else { return [] }
        var width = 1
        var capacity = base
        while capacity <= count {
            width += 1
            capacity *= base
        }
        let step = capacity / (count + 1)
        return (1...count).map { encode(($0) * step, width: width) }
    }

    public static func isValid(_ key: String) -> Bool {
        (try? validate(key)) != nil
    }

    static func validate(_ key: String) throws {
        guard !key.isEmpty, key.last != "0", key.allSatisfy({ digitIndex($0) != nil }) else {
            throw Error.invalidKey(key)
        }
    }

    private static func digitIndex(_ c: Character) -> Int? {
        guard let ascii = c.asciiValue else { return nil }
        switch ascii {
        case 48...57: return Int(ascii) - 48
        case 97...122: return Int(ascii) - 97 + 10
        default: return nil
        }
    }

    /// Precondition: inputs validated, `a < b` when `b` is present.
    private static func midpoint(_ a: [Character], _ b: [Character]?) -> String {
        if let b {
            // Skip the shared prefix ("0"-padding a), then recurse on the rest.
            var n = 0
            while n < b.count, (n < a.count ? a[n] : "0") == b[n] {
                n += 1
            }
            if n > 0 {
                return String(b[0..<n]) + midpoint(Array(a.dropFirst(n)), Array(b.dropFirst(n)))
            }
        }
        let lowDigit = a.first.flatMap(digitIndex) ?? 0
        let highDigit = b.flatMap { $0.first.flatMap(digitIndex) } ?? base
        if highDigit - lowDigit > 1 {
            return String(digits[(lowDigit + highDigit + 1) / 2])
        }
        if let b, b.count > 1 {
            return String(b[0])
        }
        return String(digits[lowDigit]) + midpoint(Array(a.dropFirst()), nil)
    }

    private static func encode(_ value: Int, width: Int) -> String {
        var chars = [Character](repeating: "0", count: width)
        var v = value
        for i in stride(from: width - 1, through: 0, by: -1) {
            chars[i] = digits[v % base]
            v /= base
        }
        // Stripping trailing zeros preserves order among equal-width keys.
        while chars.last == "0" { chars.removeLast() }
        return String(chars)
    }
}
