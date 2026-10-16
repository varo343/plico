import Foundation

// Editing primitives on RichText. Offsets are UTF-16, matching NSTextView ranges.
extension RichText {
    public var utf16Length: Int {
        runs.reduce(0) { $0 + $1.text.utf16.count }
    }

    /// Splits at `offset` (clamped), keeping each half's formatting. An offset
    /// inside a composed character (emoji, combining marks) rounds down to its start.
    public func split(atUTF16Offset offset: Int) -> (head: RichText, tail: RichText) {
        var head: [TextRun] = []
        var tail: [TextRun] = []
        var remaining = max(0, offset)
        for run in runs {
            let length = run.text.utf16.count
            if remaining >= length {
                head.append(run)
                remaining -= length
            } else if remaining == 0 {
                tail.append(run)
            } else {
                let text = run.text as NSString
                let cut = text.rangeOfComposedCharacterSequence(at: remaining).location
                var left = run
                left.text = text.substring(to: cut)
                var right = run
                right.text = text.substring(from: cut)
                head.append(left)
                tail.append(right)
                remaining = 0
            }
        }
        return (RichText(runs: head), RichText(runs: tail))
    }

    /// Concatenation; adjacent runs with equal formatting are merged.
    public static func + (lhs: RichText, rhs: RichText) -> RichText {
        RichText(runs: lhs.runs + rhs.runs)
    }
}

// Range-based formatting. Ranges are UTF-16 offsets, clamped to the text.
extension RichText {
    /// Applies `transform` to every run inside `range`, splitting runs at its edges.
    public func transformingRuns(in range: Range<Int>, _ transform: (inout TextRun) -> Void) -> RichText {
        let (head, rest) = split(atUTF16Offset: range.lowerBound)
        let (middle, tail) = rest.split(atUTF16Offset: range.count)
        var runs = middle.runs
        for index in runs.indices { transform(&runs[index]) }
        return head + RichText(runs: runs) + tail
    }

    /// Marks shared by all text in `range`. For an empty range: the marks of the
    /// character before it (what typing there would continue).
    public func commonMarks(in range: Range<Int>) -> Set<InlineMark> {
        if range.isEmpty {
            guard range.lowerBound > 0 else { return runs.first?.marks ?? [] }
            let (head, _) = split(atUTF16Offset: range.lowerBound)
            return head.runs.last?.marks ?? []
        }
        let middle = split(atUTF16Offset: range.lowerBound).tail.split(atUTF16Offset: range.count).head
        guard let first = middle.runs.first else { return [] }
        return middle.runs.dropFirst().reduce(first.marks) { $0.intersection($1.marks) }
    }

    /// The link shared by all text in `range`, if any.
    public func commonLink(in range: Range<Int>) -> URL? {
        let middle = split(atUTF16Offset: range.lowerBound).tail.split(atUTF16Offset: max(range.count, 1)).head
        let links = Set(middle.runs.map(\.link))
        return links.count == 1 ? links.first ?? nil : nil
    }

    /// Adds `mark` to the range, or removes it if the whole range already has it.
    public func toggling(_ mark: InlineMark, in range: Range<Int>) -> RichText {
        let remove = commonMarks(in: range).contains(mark) && !range.isEmpty
        return transformingRuns(in: range) { run in
            if remove { run.marks.remove(mark) } else { run.marks.insert(mark) }
        }
    }

    public func replacing(_ range: Range<Int>, with replacement: RichText) -> RichText {
        let (head, rest) = split(atUTF16Offset: range.lowerBound)
        let tail = rest.split(atUTF16Offset: range.count).tail
        return head + replacement + tail
    }
}
