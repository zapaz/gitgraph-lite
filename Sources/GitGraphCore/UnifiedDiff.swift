import Foundation

public struct UnifiedLine {
    public enum Kind { case context, removed, added, hunk, note }
    public let kind: Kind
    public let text: String
    public let oldNumber: Int?
    public let newNumber: Int?
    public let highlight: NSRange?
}

public struct UnifiedDiff {
    public let lines: [UnifiedLine]
    public let changeStarts: [Int]

    public init(_ model: VisualDiff) {
        var lines: [UnifiedLine] = [], starts: [Int] = [], changes: [DiffRow] = []
        func flush() {
            guard !changes.isEmpty else { return }
            starts.append(lines.count)
            // Unified diffs show all removed lines before all added lines in each edit.
            for row in changes {
                if let text = row.oldText { lines.append(UnifiedLine(kind: .removed, text: text, oldNumber: row.oldNumber, newNumber: nil, highlight: row.oldHighlight)) }
            }
            for row in changes {
                if let text = row.newText { lines.append(UnifiedLine(kind: .added, text: text, oldNumber: nil, newNumber: row.newNumber, highlight: row.newHighlight)) }
            }
            changes.removeAll(keepingCapacity: true)
        }
        for row in model.rows {
            if row.kind == .change { changes.append(row); continue }
            flush()
            lines.append(UnifiedLine(kind: row.kind == .hunk ? .hunk : row.kind == .note ? .note : .context, text: row.oldText ?? row.newText ?? "", oldNumber: row.oldNumber, newNumber: row.newNumber, highlight: nil))
        }
        flush()
        self.lines = lines; self.changeStarts = starts
    }
}
