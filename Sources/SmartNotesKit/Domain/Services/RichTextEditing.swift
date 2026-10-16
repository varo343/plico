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
