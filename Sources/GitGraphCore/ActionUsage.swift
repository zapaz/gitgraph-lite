import Foundation

// Stable identifiers keep counts independent of commit hashes, refs and menu labels.
public enum CommitActionID: String, CaseIterable {
    // Historical checkout IDs are retained for local usage counts; their UI actions now open dedicated workspaces.
    case checkout, createWorktree, compareHead, copyHash, copySubject
    case addTag, createBranch, cherryPick, revert, merge, rebase, reset
    case copyMessage, selectComparison, compareAnchor, compareSelected, drop
    case checkoutRemote, copyBranchName, openWorktree, createBranchWorktree
    case renameBranch, deleteBranch, copyTagName, deleteTag
    case continueOperation, abortOperation, createLocalFromRemote

    case copyShortHash, pushBranch, pullBranch, pushTag, copyWorktreePath, revealWorktree, deleteWorktree

    public var title: String {
        switch self {
        case .copyShortHash: return "Copy Short Commit Hash"
        case .pushBranch: return "Push to origin"
        case .pullBranch: return "Pull from origin"
        case .pushTag: return "Publish on origin"
        case .copyWorktreePath: return "Copy Worktree Path"
        case .revealWorktree: return "Show in Finder"
        case .deleteWorktree: return "Delete Worktree…"
        case .checkout: return "Open Branch…"
        case .createWorktree: return "Create and Open Branch Here…"
        case .compareHead: return "Compare with HEAD"
        case .copyHash: return "Copy Commit Hash to Clipboard"
        case .copySubject: return "Copy Commit Subject to Clipboard"
        case .addTag: return "Add Tag..."
        case .createBranch: return "Create Local Branch"
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
        case .checkoutRemote: return "Open Remote Branch Locally…"
        case .copyBranchName: return "Copy Branch Name"
        case .openWorktree: return "Open Worktree"
        case .createBranchWorktree: return "Open Branch…"
        case .renameBranch: return "Rename Branch…"
        case .deleteBranch: return "Delete Branch…"
        case .copyTagName: return "Copy Tag Name"
        case .deleteTag: return "Delete Tag…"
        case .continueOperation: return "Continue Operation…"
        case .abortOperation: return "Abort Operation…"
        case .createLocalFromRemote: return "Create Local Branch"
        }
    }
}

public enum ActionItemKind: String { case commit, branch, worktree, tag }

public final class ActionUsage {
    private let defaults: UserDefaults
    private let key = "commitActionClickCounts.v1"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private var counts: [String: Int] {
        (defaults.dictionary(forKey: key) ?? [:]).reduce(into: [:]) { result, entry in
            if let count = entry.value as? Int, count >= 0 { result[entry.key] = count }
        }
    }
    private func storageKey(_ id: CommitActionID, kind: ActionItemKind) -> String {
        kind == .commit ? id.rawValue : kind.rawValue + "." + id.rawValue
    }
    public func count(_ id: CommitActionID, kind: ActionItemKind = .commit) -> Int {
        let values = counts
        return values[storageKey(id, kind: kind)] ?? values[id.rawValue] ?? 0
    }
    public func record(_ id: CommitActionID, kind: ActionItemKind = .commit) {
        var values = counts
        let key = storageKey(id, kind: kind)
        let previous = values[key] ?? values[id.rawValue] ?? 0
        values[key] = previous == Int.max ? Int.max : previous+1
        defaults.set(values, forKey: self.key)
    }
    public func ranked(_ ids: [CommitActionID], kind: ActionItemKind = .commit) -> [CommitActionID] {
        let values = counts
        var seen = Set<CommitActionID>()
        let unique = ids.filter { seen.insert($0).inserted }
        let priority = Dictionary(uniqueKeysWithValues: unique.enumerated().map { ($0.element, $0.offset) })
        return unique.sorted {
            let a = values[storageKey($0, kind: kind)] ?? values[$0.rawValue] ?? 0
            let b = values[storageKey($1, kind: kind)] ?? values[$1.rawValue] ?? 0
            return a != b ? a > b : priority[$0]! < priority[$1]!
        }
    }
}
