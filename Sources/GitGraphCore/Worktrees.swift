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
        return parts.joined(separator: " · ")
    }
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
        try parseWorktrees(worktreeMetadata(at: path)).map { tree in
            let status = tree.exists && !tree.isBare ? try? run(["status", "--porcelain=v1", "-z", "--untracked-files=normal"], at: tree.path) : nil
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
    }
    public static func worktreeSummary(_ worktrees: [GitWorktree]) -> String {
        worktrees.map { "\($0.path)\0\($0.head)\0\($0.branch ?? "")\0\($0.stateLabel)\0\($0.lockReason ?? "")" }.joined(separator: "\n")
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
                guard !trees.contains(where: { $0.branch == "refs/heads/" + name }) else { throw GitError(message: "This branch is already checked out in a worktree. Open that worktree instead.") }
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
            return output + (preservedHead.map { "\nDetached HEAD saved as branch \($0)." } ?? "")
        } catch {
            if let preservedHead { throw GitError(message: error.localizedDescription + "\nDetached HEAD saved as branch \(preservedHead).") }
            throw error
        }
    }
}
