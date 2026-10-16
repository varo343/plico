import Testing
@testable import SmartNotesKit

@Suite struct RankTests {
    @Test func initialKeyIsValid() {
        #expect(Rank.isValid(Rank.initial))
    }

    @Test func betweenProducesStrictlyOrderedKeys() throws {
        let a = try Rank.between(nil, nil)
        let b = try Rank.between(a, nil)
        let c = try Rank.between(nil, a)
        let mid = try Rank.between(a, b)
        #expect(c < a && a < mid && mid < b)
        for key in [a, b, c, mid] { #expect(Rank.isValid(key)) }
    }

    @Test func adjacentAndPrefixKeysStillHaveRoomBetween() throws {
        // Cases that force recursion / extending the key.
        let pairs: [(String?, String?)] = [("a", "b"), ("a", "a1"), ("0i", "1"), (nil, "01"), ("z", nil), ("yz", "z")]
        for (lower, upper) in pairs {
            let key = try Rank.between(lower, upper)
            #expect(Rank.isValid(key), "invalid key \(key)")
            if let lower { #expect(lower < key, "\(lower) !< \(key)") }
            if let upper { #expect(key < upper, "\(key) !< \(upper)") }
        }
    }

    @Test func rejectsInvalidOrUnorderedInput() {
        #expect(throws: Rank.Error.outOfOrder("b", "a")) { try Rank.between("b", "a") }
        #expect(throws: Rank.Error.outOfOrder("a", "a")) { try Rank.between("a", "a") }
        #expect(throws: Rank.Error.invalidKey("a0")) { try Rank.between("a0", nil) }
        #expect(throws: Rank.Error.invalidKey("A")) { try Rank.between(nil, "A") }
        #expect(throws: Rank.Error.invalidKey("")) { try Rank.between("", nil) }
    }

    @Test func randomInsertionsKeepOrder() throws {
        // Deterministic pseudo-random sequence of inserts at arbitrary positions.
        var generator = SplitMix64(seed: 42)
        var keys: [String] = []
        for _ in 0..<2_000 {
            let index = keys.isEmpty ? 0 : Int.random(in: 0...keys.count, using: &generator)
            let lower = index > 0 ? keys[index - 1] : nil
            let upper = index < keys.count ? keys[index] : nil
            keys.insert(try Rank.between(lower, upper), at: index)
        }
        #expect(keys == keys.sorted())
        #expect(Set(keys).count == keys.count)
    }

    @Test(arguments: [0, 1, 2, 35, 36, 100, 1_500])
    func evenlySpacedIsSortedUniqueAndValid(count: Int) {
        let keys = Rank.evenlySpaced(count)
        #expect(keys.count == count)
        #expect(keys == keys.sorted())
        #expect(Set(keys).count == count)
        #expect(keys.allSatisfy(Rank.isValid))
    }
}

/// Small seeded RNG so the randomized test is reproducible.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
