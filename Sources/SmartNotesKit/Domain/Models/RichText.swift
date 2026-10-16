import Foundation

/// Inline formatting marks supported in v1.
public enum InlineMark: String, Codable, CaseIterable, Sendable, Comparable {
    case bold, italic, underline, strikethrough, code

    public static func < (lhs: InlineMark, rhs: InlineMark) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Small, deliberate set of font families (no free-form font picker in v1).
public enum FontFamilyPreset: String, Codable, CaseIterable, Sendable {
    case system, serif, rounded, monospaced
}

/// Stable text-size presets from the design spec (12, 14, 16, 18, 22, 28 pt).
public enum FontSizePreset: Int, Codable, CaseIterable, Sendable {
    case small = 12
    case compact = 14
    case body = 16
    case large = 18
    case title = 22
    case display = 28

    public var points: Double { Double(rawValue) }
}

/// A span of text sharing the same formatting.
public struct TextRun: Hashable, Sendable {
    public var text: String
    public var marks: Set<InlineMark>
    public var link: URL?
    public var fontFamily: FontFamilyPreset?
    public var fontSize: FontSizePreset?

    public init(
        _ text: String,
        marks: Set<InlineMark> = [],
        link: URL? = nil,
        fontFamily: FontFamilyPreset? = nil,
        fontSize: FontSizePreset? = nil
    ) {
        self.text = text
        self.marks = marks
        self.link = link
        self.fontFamily = fontFamily
        self.fontSize = fontSize
    }

    func hasSameAttributes(as other: TextRun) -> Bool {
        marks == other.marks && link == other.link && fontFamily == other.fontFamily && fontSize == other.fontSize
    }
}

extension TextRun: Codable {
    private enum CodingKeys: String, CodingKey {
        case text, marks, link, fontFamily, fontSize
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        marks = Set(try c.decodeIfPresent([InlineMark].self, forKey: .marks) ?? [])
        if let raw = try c.decodeIfPresent(String.self, forKey: .link) {
            guard let url = URL(string: raw) else {
                throw DecodingError.dataCorruptedError(forKey: .link, in: c, debugDescription: "Invalid link URL")
            }
            link = url
        } else {
            link = nil
        }
        fontFamily = try c.decodeIfPresent(FontFamilyPreset.self, forKey: .fontFamily)
        fontSize = try c.decodeIfPresent(FontSizePreset.self, forKey: .fontSize)
    }

    // Omits default values and sorts marks so the encoding is deterministic.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(text, forKey: .text)
        if !marks.isEmpty { try c.encode(marks.sorted(), forKey: .marks) }
        try c.encodeIfPresent(link?.absoluteString, forKey: .link)
        try c.encodeIfPresent(fontFamily, forKey: .fontFamily)
        try c.encodeIfPresent(fontSize, forKey: .fontSize)
    }
}

/// Versioned, platform-independent rich text payload for one block.
///
/// Serialized as `{ "version": 1, "runs": [{ "text": "...", "marks": ["bold"] }] }`.
/// We deliberately avoid opaque NSAttributedString archives so the format can be
/// migrated and tested. Newlines inside a block are soft line breaks.
public struct RichText: Hashable, Sendable {
    public static let currentVersion = 1

    public private(set) var runs: [TextRun]

    public init(runs: [TextRun]) {
        self.runs = Self.normalized(runs)
    }

    public init(plain text: String) {
        self.init(runs: [TextRun(text)])
    }

    public static let empty = RichText(runs: [])

    public var plainText: String { runs.map(\.text).joined() }

    public var isEmpty: Bool { runs.isEmpty }

    /// Drops empty runs and merges adjacent runs with identical attributes, so
    /// equal-looking content always has one canonical representation.
    static func normalized(_ runs: [TextRun]) -> [TextRun] {
        var result: [TextRun] = []
        for run in runs where !run.text.isEmpty {
            if let last = result.last, last.hasSameAttributes(as: run) {
                result[result.count - 1].text += run.text
            } else {
                result.append(run)
            }
        }
        return result
    }
}

public enum RichTextCodingError: Error, Equatable {
    case unsupportedVersion(Int)
}

extension RichText: Codable {
    private enum CodingKeys: String, CodingKey {
        case version, runs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .version)
        guard version == Self.currentVersion else {
            // Future migrations hook in here; never guess at an unknown format.
            throw RichTextCodingError.unsupportedVersion(version)
        }
        self.init(runs: try c.decode([TextRun].self, forKey: .runs))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentVersion, forKey: .version)
        try c.encode(runs, forKey: .runs)
    }

    public func encodedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public static func decode(from data: Data) throws -> RichText {
        try JSONDecoder().decode(RichText.self, from: data)
    }
}
