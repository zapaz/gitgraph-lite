import Foundation

// Immutable search text is prepared once per loaded history, not once per keystroke.
public struct HistorySearchIndex {
    private let text: [String]
    public init(_ commits: [Commit]) {
        text = commits.map { "\($0.subject) \($0.author) \($0.id) \($0.decorations)".lowercased() }
    }
    public func matching(_ query: String) -> [Int] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty { return Array(text.indices) }
        return text.indices.filter { text[$0].contains(normalized) }
    }
}
