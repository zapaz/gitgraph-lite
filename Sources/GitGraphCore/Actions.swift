import Foundation

public struct GitReference {
    public let name: String
    public let target: String
    public let symbolic: Bool
    public init(name: String, target: String, symbolic: Bool = false) { self.name = name; self.target = target; self.symbolic = symbolic }
    public var isBranch: Bool { name.hasPrefix("refs/heads/") }
    public var isTag: Bool { name.hasPrefix("refs/tags/") }
    public var shortName: String {
        for prefix in ["refs/heads/", "refs/tags/", "refs/remotes/"] where name.hasPrefix(prefix) { return String(name.dropFirst(prefix.count)) }
        return name
    }
}

public enum GitAction {
    case renameBranch(old: String, new: String), deleteBranch(String)
    case addTag(name: String, commit: String, message: String), deleteTag(String)
    case cherryPick(commit: String, mainline: Int?), revert(commit: String, mainline: Int?)
    case merge(commit: String, noFastForward: Bool, squash: Bool)
    case rebase(String), reset(commit: String, mode: String), drop(String)
    case continueOperation(String), abortOperation(String)
}

public struct ActionResult {
    public let output: String
    public let backup: String?
}

extension Git {
    public static func references(at path: String) throws -> [GitReference] {
        let data = try string(["for-each-ref", "--format=%(refname)%00%(objectname)%00%(*objectname)%00%(symref)"], at: path)
        return data.components(separatedBy: "\n").compactMap { line in
            let fields = line.components(separatedBy: "\0")
            guard fields.count == 4 else { return nil }
            return GitReference(name: fields[0], target: fields[2].isEmpty ? fields[1] : fields[2], symbolic: !fields[3].isEmpty)
        }
    }

    public static func pendingOperation(at path: String) throws -> String? {
        let directory = URL(fileURLWithPath: try string(["rev-parse", "--absolute-git-dir"], at: path), isDirectory: true)
        for (file, operation) in [("rebase-merge", "rebase"), ("rebase-apply", "rebase"), ("CHERRY_PICK_HEAD", "cherry-pick"), ("REVERT_HEAD", "revert"), ("MERGE_HEAD", "merge")] {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent(file).path) { return operation }
        }
        return nil
    }

    public static func perform(_ action: GitAction, at path: String, expectedSignature: String? = nil) throws -> ActionResult {
        if let expectedSignature, try signature(at: path) != expectedSignature {
            throw GitError(message: "The repository changed while this dialog was open. Refresh the graph and try again.")
        }
        let recovery: Bool
        switch action { case .continueOperation, .abortOperation: recovery = true; default: recovery = false }
        if !recovery, let pending = try pendingOperation(at: path) {
            throw GitError(message: "A \(pending) is already in progress. Resolve conflicts and use Continue, or choose Abort from the commit menu.")
        }
        if expectedSignature != nil { try validateWorkspace(at: path) }
        var args: [String] = [], backup: String?
        var needsClean = false, needsBranch = false, createsBackup = false
        let occupiedBranch: String?
        switch action {
        case .deleteBranch(let name): occupiedBranch = name
        case .renameBranch(let old, _): occupiedBranch = old
        default: occupiedBranch = nil
        }
        if let name = occupiedBranch, let tree = try worktrees(at: path).first(where: { $0.branch == "refs/heads/" + name || $0.assignedBranch == "refs/heads/" + name }) {
            throw GitError(message: "Branch \(name) is checked out in worktree \(tree.path). A branch in use cannot be renamed or deleted here.")
        }
        switch action {
        case .renameBranch(let old, let new): try validateBranch(new, at: path); args = ["branch", "-m", "--", old, new]
        case .deleteBranch(let name): args = ["branch", "-d", "--", name]
        case .addTag(let name, let commit, let message):
            guard !name.hasPrefix("-"), !name.isEmpty else { throw GitError(message: "Enter a valid tag name.") }
            _ = try run(["check-ref-format", "refs/tags/" + name], at: path)
            args = message.isEmpty ? ["tag", name, commit] : ["tag", "-a", name, "-m", message, commit]
        case .deleteTag(let name): args = ["tag", "-d", "--", name]
        case .cherryPick(let sha, let mainline):
            args = ["cherry-pick"] + (mainline.map { ["-m", String($0)] } ?? []) + [sha]; needsClean = true
        case .revert(let sha, let mainline):
            args = ["revert", "--no-edit"] + (mainline.map { ["-m", String($0)] } ?? []) + [sha]; needsClean = true
        case .merge(let sha, let noFF, let squash):
            args = ["merge", "--no-edit"] + (squash ? ["--squash"] : noFF ? ["--no-ff"] : []) + [sha]; needsClean = true; needsBranch = true
        case .rebase(let sha): args = ["rebase", "--rebase-merges", sha]; needsClean = true; needsBranch = true; createsBackup = true
        case .reset(let sha, let mode):
            guard ["soft", "mixed", "hard"].contains(mode) else { throw GitError(message: "Invalid reset mode.") }
            args = ["reset", "--" + mode, sha]; createsBackup = true
        case .drop(let sha):
            let parents = try string(["show", "-s", "--format=%P", sha, "--"], at: path).split(separator: " ")
            guard parents.count == 1 else { throw GitError(message: "Drop is supported for ordinary commits with one parent. Root and merge commits cannot be dropped here.") }
            guard (try? run(["merge-base", "--is-ancestor", sha, "HEAD"], at: path)) != nil else { throw GitError(message: "This commit is not on the current branch's history.") }
            args = ["rebase", "--rebase-merges", "--onto", String(parents[0]), sha]
            needsClean = true; needsBranch = true; createsBackup = true
        case .continueOperation(let operation):
            try validateRecovery(operation, at: path); args = [operation, "--continue"]
        case .abortOperation(let operation):
            try validateRecovery(operation, at: path); args = [operation, "--abort"]
        }
        if needsBranch, (try? run(["symbolic-ref", "--quiet", "HEAD"], at: path)) == nil {
            throw GitError(message: "Open or create a worktree on a local branch first. This operation is unavailable with a detached HEAD.")
        }
        if needsClean, !(try run(["status", "--porcelain=v1", "-z"], at: path)).isEmpty {
            throw GitError(message: "Commit or stash your local changes first. This action requires a clean working tree.")
        }
        if createsBackup {
            let name = "gitgraph-backup/" + String(UUID().uuidString.prefix(8)).lowercased()
            _ = try run(["branch", name, "HEAD"], at: path); backup = name
        }
        do {
            let output = try string(args, at: path)
            return ActionResult(output: output, backup: backup)
        } catch {
            let pending = try? pendingOperation(at: path)
            var message = error.localizedDescription
            if let backup { message += "\n\nPrevious HEAD saved as branch \(backup)." }
            if let pending { message += "\n\nA \(pending) is in progress. Resolve conflicts in your editor, stage the resolved files, then use Continue from the commit menu. Use Abort to return to the previous state." }
            throw GitError(message: message)
        }
    }

    static func validateBranch(_ name: String, at path: String) throws {
        guard !name.isEmpty, !name.hasPrefix("-"), name != "HEAD" else { throw GitError(message: "Enter a valid branch name.") }
        _ = try run(["check-ref-format", "--branch", name], at: path)
    }
    private static func validateRecovery(_ operation: String, at path: String) throws {
        guard ["merge", "rebase", "cherry-pick", "revert"].contains(operation), try pendingOperation(at: path) == operation else {
            throw GitError(message: "This operation is no longer in progress. Refresh and try again.")
        }
    }
}
