import Foundation

// Stable identifiers keep counts independent of commit hashes, refs and menu labels.
public enum CommitActionID: String, CaseIterable {
    case checkout, createWorktree, compareHead, copyHash, copySubject
    case addTag, createBranch, cherryPick, revert, merge, rebase, reset
    case copyMessage, selectComparison, compareAnchor, compareSelected, drop
    case checkoutRemote, copyBranchName, openWorktree, createBranchWorktree
    case renameBranch, deleteBranch, copyTagName, deleteTag
    case continueOperation, abortOperation

    public var title: String {
        switch self {
        case .checkout: return "Checkout..."
        case .createWorktree: return "Create Worktree Here..."
        case .compareHead: return "Compare with HEAD"
        case .copyHash: return "Copy Commit Hash to Clipboard"
        case .copySubject: return "Copy Commit Subject to Clipboard"
        case .addTag: return "Add Tag..."
        case .createBranch: return "Create Branch..."
        case .cherryPick: return "Cherry Pick..."
        case .revert: return "Revert..."
        case .merge: return "Merge into current branch..."
        case .rebase: return "Rebase current branch on this Commit..."
        case .reset: return "Reset current branch to this Commit..."
        case .copyMessage: return "Copy Full Commit Message"
        case .selectComparison: return "Select for Comparison"
        case .compareAnchor: return "Compare with Selected Commit"
        case .compareSelected: return "Compare Selected Commits"
        case .drop: return "Drop Commit..."
        case .checkoutRemote: return "Checkout Remote Branch in This Worktree"
        case .copyBranchName: return "Copy Branch Name"
        case .openWorktree: return "Open Worktree"
        case .createBranchWorktree: return "Create Worktree on This Branch…"
        case .renameBranch: return "Rename Branch…"
        case .deleteBranch: return "Delete Branch…"
        case .copyTagName: return "Copy Tag Name"
        case .deleteTag: return "Delete Tag…"
        case .continueOperation: return "Continue Operation…"
        case .abortOperation: return "Abort Operation…"
        }
    }
}

public final class ActionUsage {
    private let defaults: UserDefaults
    private let key = "commitActionClickCounts.v1"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private var counts: [String: Int] {
        (defaults.dictionary(forKey: key) ?? [:]).reduce(into: [:]) { result, entry in
            if let count = entry.value as? Int, count >= 0 { result[entry.key] = count }
        }
    }
    public func count(_ id: CommitActionID) -> Int { counts[id.rawValue] ?? 0 }
    public func record(_ id: CommitActionID) {
        var values = counts
        let previous = values[id.rawValue] ?? 0
        values[id.rawValue] = previous == Int.max ? Int.max : previous+1
        defaults.set(values, forKey: key)
    }
    public func ranked(_ ids: [CommitActionID]) -> [CommitActionID] {
        let values = counts
        let priority = Dictionary(uniqueKeysWithValues: CommitActionID.allCases.enumerated().map { ($0.element, $0.offset) })
        return Array(Set(ids)).sorted {
            let a = values[$0.rawValue] ?? 0, b = values[$1.rawValue] ?? 0
            return a != b ? a > b : priority[$0]! < priority[$1]!
        }
    }
}
