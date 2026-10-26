import Foundation

public struct DiffRow {
    public enum Kind { case context, change, hunk, note }
    public let kind: Kind
    public let oldNumber: Int?
    public let newNumber: Int?
    public let oldText: String?
    public let newText: String?
    public let oldHighlight: NSRange?
    public let newHighlight: NSRange?
}

public struct VisualDiff {
    public let rows: [DiffRow]
    public let additions: Int
    public let deletions: Int
    public let changeStarts: [Int]
    public let isBinary: Bool

    public static func parse(_ patch: String) -> VisualDiff {
        var rows: [DiffRow] = [], removed: [(Int, String)] = [], added: [(Int, String)] = []
        var old = 0, new = 0, inHunk = false, additions = 0, deletions = 0
        var starts: [Int] = []
        func flush() {
            guard !removed.isEmpty || !added.isEmpty else { return }
            starts.append(rows.count)
            for i in 0..<max(removed.count, added.count) {
                let a = i < removed.count ? removed[i] : nil, b = i < added.count ? added[i] : nil
                let ranges = a != nil && b != nil ? highlights(a!.1, b!.1) : (nil, nil)
                rows.append(DiffRow(kind: .change, oldNumber: a?.0, newNumber: b?.0, oldText: a?.1, newText: b?.1, oldHighlight: ranges.0, newHighlight: ranges.1))
            }
            removed.removeAll(keepingCapacity: true); added.removeAll(keepingCapacity: true)
        }
        let regex = try! NSRegularExpression(pattern: "^@@ -([0-9]+)(?:,[0-9]+)? \\+([0-9]+)(?:,[0-9]+)? @@")
        let binary = patch.contains("Binary files ") || patch.contains("GIT binary patch")
        // Split only on LF: String's Character splitting would treat CRLF as one grapheme.
        var lines = patch.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        for line in lines {
            if line.hasPrefix("@@ ") {
                flush()
                let ns = line as NSString
                guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { inHunk = false; continue }
                old = Int(ns.substring(with: match.range(at: 1))) ?? 0
                new = Int(ns.substring(with: match.range(at: 2))) ?? 0
                inHunk = true
                rows.append(DiffRow(kind: .hunk, oldNumber: nil, newNumber: nil, oldText: line, newText: line, oldHighlight: nil, newHighlight: nil))
            } else if inHunk && line.hasPrefix("-") {
                removed.append((old, String(line.dropFirst()))); old += 1; deletions += 1
            } else if inHunk && line.hasPrefix("+") {
                added.append((new, String(line.dropFirst()))); new += 1; additions += 1
            } else if inHunk && line.hasPrefix(" ") {
                flush()
                rows.append(DiffRow(kind: .context, oldNumber: old, newNumber: new, oldText: String(line.dropFirst()), newText: String(line.dropFirst()), oldHighlight: nil, newHighlight: nil))
                old += 1; new += 1
            } else if line.hasPrefix("\\ No newline") || line.hasPrefix("[Preview truncated") {
                flush()
                rows.append(DiffRow(kind: .note, oldNumber: nil, newNumber: nil, oldText: line, newText: line, oldHighlight: nil, newHighlight: nil))
            } else if line.hasPrefix("diff --git ") { flush(); inHunk = false }
        }
        flush()
        return VisualDiff(rows: rows, additions: additions, deletions: deletions, changeStarts: starts, isBinary: binary)
    }

    public static func highlights(_ before: String, _ after: String) -> (NSRange?, NSRange?) {
        let a = Array(before), b = Array(after)
        var prefix = 0, suffix = 0
        while prefix < min(a.count, b.count) && a[prefix] == b[prefix] { prefix += 1 }
        while suffix < min(a.count, b.count) - prefix && a[a.count-1-suffix] == b[b.count-1-suffix] { suffix += 1 }
        func range(_ characters: [Character]) -> NSRange? {
            let text = String(characters[prefix..<(characters.count-suffix)])
            guard !text.isEmpty else { return nil }
            return NSRange(location: String(characters.prefix(prefix)).utf16.count, length: text.utf16.count)
        }
        return (range(a), range(b))
    }
}
