import Foundation

public struct GitWorktree {
    public let path: String
    public let head: String
    public let branch: String?
    public let isMain: Bool
    public let isBare: Bool
    public let isLocked: Bool
    public let lockReason: String?
    public let isPrunable: Bool
    public let pruneReason: String?
    public let changedFiles: Int?
    public let exists: Bool
    public var assignedBranch: String? = nil
    public var associationIssue: String? = nil
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
    public var branchLabel: String { branch.map { $0.replacingOccurrences(of: "refs/heads/", with: "") } ?? (isBare ? "Bare repository" : "Detached · " + String(head.prefix(8))) }
    public var stateLabel: String {
        var parts: [String] = []
        if isMain { parts.append("Main") }
        if !exists { parts.append("Missing") }
        else if let count = changedFiles { parts.append(count == 0 ? "Clean" : "\(count) change\(count == 1 ? "" : "s")") }
        else if !isBare { parts.append("Status unavailable") }
        if isLocked { parts.append("Locked") }
        if isPrunable { parts.append("Prunable") }
        if associationIssue != nil { parts.append("Association changed") }
        return parts.joined(separator: " · ")
    }
}

private final class WorktreeStatuses {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func store(_ data: Data, at path: String) { lock.lock(); defer { lock.unlock() }; values[path] = data }
    func value(at path: String) -> Data? { lock.lock(); defer { lock.unlock() }; return values[path] }
}

public enum WorktreeSource {
    case newBranch(name: String, start: String)
    case existingBranch(String)
    case detached(String)
}
public enum WorktreeAction {
    case add(path: String, source: WorktreeSource)
    case remove(String)
    case move(path: String, destination: String)
    case lock(path: String, reason: String)
    case unlock(String)
}

extension Git {
    public static func samePath(_ a: String, _ b: String) -> Bool {
        URL(fileURLWithPath: a).standardizedFileURL.resolvingSymlinksInPath().path == URL(fileURLWithPath: b).standardizedFileURL.resolvingSymlinksInPath().path
    }
    public static func worktreeMetadata(at path: String) throws -> Data { try run(["worktree", "list", "--porcelain", "-z"], at: path) }

    public static func parseWorktrees(_ data: Data) -> [GitWorktree] {
        var result: [GitWorktree] = [], fields: [String: String] = [:]
        func flush() {
            guard let path = fields["worktree"] else { return }
            result.append(GitWorktree(path: path, head: fields["HEAD"] ?? "", branch: fields["branch"], isMain: result.isEmpty, isBare: fields["bare"] != nil, isLocked: fields["locked"] != nil, lockReason: fields["locked"], isPrunable: fields["prunable"] != nil, pruneReason: fields["prunable"], changedFiles: nil, exists: FileManager.default.fileExists(atPath: path)))
            fields.removeAll()
        }
        for field in data.split(separator: 0, omittingEmptySubsequences: false) {
            if field.isEmpty { flush(); continue }
            let text = String(decoding: field, as: UTF8.self)
            let split = text.firstIndex(of: " ")
            fields[split.map { String(text[..<$0]) } ?? text] = split.map { String(text[text.index(after: $0)...]) } ?? ""
        }
        flush(); return result
    }

    public static func worktrees(at path: String) throws -> [GitWorktree] {
        try worktrees(at: path, retryAfterChange: true)
    }
    private static func worktrees(at path: String, retryAfterChange: Bool) throws -> [GitWorktree] {
        let metadata = try worktreeMetadata(at: path)
        let listed = parseWorktrees(metadata)
        let statuses = WorktreeStatuses(), queue = OperationQueue()
        queue.maxConcurrentOperationCount = 4; queue.qualityOfService = .userInitiated
        // Independent worktree indexes can be inspected together without serially
        // waiting for every directory scan. Keep concurrency bounded on big repos.
        for tree in listed where tree.exists && !tree.isBare {
            queue.addOperation {
                if let data = try? run(["status", "--porcelain=v1", "-z", "--untracked-files=normal"], at: tree.path) {
                    statuses.store(data, at: tree.path)
                }
            }
        }
        queue.waitUntilAllOperationsAreFinished()
        let trees = listed.map { tree in
            let status = statuses.value(at: tree.path)
            var count = 0
            if let status {
                let records = status.split(separator: 0); var i = 0
                while i < records.count {
                    let prefix = String(decoding: records[i].prefix(2), as: UTF8.self)
                    count += 1; i += (prefix.contains("R") || prefix.contains("C")) ? 2 : 1
                }
            }
            return GitWorktree(path: tree.path, head: tree.head, branch: tree.branch, isMain: tree.isMain, isBare: tree.isBare, isLocked: tree.isLocked, lockReason: tree.lockReason, isPrunable: tree.isPrunable, pruneReason: tree.pruneReason, changedFiles: status == nil ? nil : count, exists: tree.exists)
        }
        do { return try WorkspaceAssociations.annotate(trees, at: path) }
        catch {
            // Another Git tool can remove a temporary worktree while its status is
            // being scanned. Retry once only when the registration actually changed.
            if retryAfterChange, let current = try? worktreeMetadata(at: path), current != metadata {
                return try worktrees(at: path, retryAfterChange: false)
            }
            throw error
        }
    }
    static func worktreeRegistration(_ worktrees: [GitWorktree]) -> [String] {
        worktrees.map { tree in
            [tree.path, tree.head, tree.branch ?? "", tree.isMain ? "main" : "linked", tree.isBare ? "bare" : "", tree.exists ? "exists" : "missing", tree.isLocked ? "locked" : "", tree.lockReason ?? "", tree.isPrunable ? "prunable" : "", tree.pruneReason ?? ""].joined(separator: "\0")
        }
    }
    public static func worktreeSummary(_ worktrees: [GitWorktree]) -> String {
        worktrees.map { "\($0.path)\0\($0.head)\0\($0.branch ?? "")\0\($0.stateLabel)\0\($0.lockReason ?? "")\0\($0.assignedBranch ?? "")\0\($0.associationIssue ?? "")" }.joined(separator: "\n")
    }

    public static func performWorktree(_ action: WorktreeAction, at path: String) throws -> String {
        let trees = try worktrees(at: path)
        func target(_ location: String, removing: Bool = false) throws -> GitWorktree {
            guard let tree = trees.first(where: { samePath($0.path, location) }) else { throw GitError(message: "This worktree is no longer registered. Refresh the list.") }
            guard !tree.isMain else { throw GitError(message: "The main worktree cannot be moved, locked or removed here.") }
            if removing {
                guard !samePath(tree.path, path) else { throw GitError(message: "Open another worktree before moving or removing the active worktree.") }
                guard !tree.isLocked else { throw GitError(message: "Unlock this worktree before moving or removing it.") }
                guard tree.exists else { throw GitError(message: "This worktree is missing. Restore its folder or use git worktree prune after checking its location.") }
                guard tree.changedFiles == 0 else { throw GitError(message: "This worktree has local changes, or its status cannot be read. Commit or stash changes before removing or moving it.") }
                guard try pendingOperation(at: tree.path) == nil else { throw GitError(message: "Finish or abort the pending Git operation in this worktree first.") }
            }
            return tree
        }
        func destination(_ raw: String) throws -> String {
            guard raw.hasPrefix("/"), raw != "/" else { throw GitError(message: "Choose an absolute path for the new worktree folder.") }
            let url = URL(fileURLWithPath: raw).standardizedFileURL
            guard !FileManager.default.fileExists(atPath: url.path) else { throw GitError(message: "The destination already exists. Choose a new folder name.") }
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path, isDirectory: &directory), directory.boolValue else { throw GitError(message: "The destination's parent folder does not exist.") }
            return url.path
        }
        var args: [String], preservedHead: String?
        switch action {
        case .add(let location, let source):
            let dest = try destination(location)
            switch source {
            case .newBranch(let name, let start):
                try validateBranch(name, at: path)
                let commit = try string(["rev-parse", "--verify", "--end-of-options", start + "^{commit}"], at: path)
                args = ["worktree", "add", "-b", name, "--", dest, commit]
            case .existingBranch(let name):
                try validateBranch(name, at: path)
                guard !trees.contains(where: { $0.branch == "refs/heads/" + name || $0.assignedBranch == "refs/heads/" + name }) else { throw GitError(message: "This branch is already checked out in a worktree. Open that worktree instead.") }
                _ = try run(["show-ref", "--verify", "refs/heads/" + name], at: path)
                args = ["worktree", "add", "--", dest, name]
            case .detached(let start):
                let commit = try string(["rev-parse", "--verify", "--end-of-options", start + "^{commit}"], at: path)
                args = ["worktree", "add", "--detach", "--", dest, commit]
            }
        case .remove(let location):
            let tree = try target(location, removing: true)
            if tree.branch == nil && !tree.head.isEmpty {
                let name = "gitgraph-backup/worktree-" + String(UUID().uuidString.prefix(8)).lowercased()
                _ = try run(["branch", name, tree.head], at: path); preservedHead = name
            }
            args = ["worktree", "remove", "--", tree.path]
        case .move(let location, let newPath): let tree = try target(location, removing: true); args = ["worktree", "move", "--", tree.path, try destination(newPath)]
        case .lock(let location, let reason): let tree = try target(location); args = ["worktree", "lock", "--reason", reason, "--", tree.path]
        case .unlock(let location): let tree = try target(location); args = ["worktree", "unlock", "--", tree.path]
        }
        do {
            let output = try string(args, at: path)
            _ = try WorkspaceAssociations.annotate(parseWorktrees(worktreeMetadata(at: path)), at: path)
            return output + (preservedHead.map { "\nDetached HEAD saved as branch \($0)." } ?? "")
        } catch {
            if let preservedHead { throw GitError(message: error.localizedDescription + "\nDetached HEAD saved as branch \(preservedHead).") }
            throw error
        }
    }
}
