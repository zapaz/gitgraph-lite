import Foundation

public enum RepositoryItemAction {
    case pushBranch(String), pullBranch(String), pushTag(String)
    /// Deletes the tag on every remote that has it, then locally. No remote is skipped or chosen by the user.
    case deleteTagEverywhere(String)
    /// Publishes the tag on every configured remote, without force.
    case pushTagEverywhere(String)
    case renameBranch(old: String, new: String)
}

extension Git {
    public static func performItem(_ action: RepositoryItemAction, at path: String, expectedSignature: String? = nil) throws -> ActionResult {
        if let expectedSignature, try signature(at: path) != expectedSignature {
            throw GitError(message: "The repository changed. Refresh and try again.")
        }
        let output: String
        switch action {
        case .renameBranch(let old, let new):
            try validateBranch(old, at: path); try validateBranch(new, at: path)
            output = try WorkspaceAssociations.renameBranch(old: old, new: new, at: path)
        case .pushBranch(let name):
            try validateBranch(name, at: path)
            output = try pushReference("refs/heads/" + name, at: path)
        case .pushTag(let name):
            let ref = "refs/tags/" + name
            _ = try run(["check-ref-format", ref], at: path)
            output = try pushReference(ref, at: path)
        case .deleteTagEverywhere(let name):
            output = try deleteTagEverywhere(name, at: path)
        case .pushTagEverywhere(let name):
            output = try pushTagEverywhere(name, at: path)
        case .pullBranch(let name):
            try validateBranch(name, at: path); try requireOrigin(at: path)
            let reference = "refs/heads/" + name
            let existing = try? string(["show-ref", "--verify", "--hash", reference], at: path)
            let trees = try worktrees(at: path)
            let referenceOnly = existing != nil && canPullWithoutEditingWorkspace(name, worktrees: trees)
            if !referenceOnly, let tree = trees.first(where: { $0.branch == reference || $0.assignedBranch == reference }) {
                try validatePullWorkspace(tree.path, branch: reference)
            }
            _ = try run(["-c", "fetch.recurseSubmodules=false", "fetch", "--no-tags", "--no-prune", "--no-prune-tags", "--no-recurse-submodules", "--", "origin", "+refs/heads/" + name + ":refs/remotes/origin/" + name], at: path)
            let fetched = try string(["rev-parse", "--verify", "refs/remotes/origin/" + name + "^{commit}"], at: path)
            if referenceOnly, let existing {
                // An externally switched workspace still belongs to its original branch
                // in our metadata. Update the unused ref without repairing that binding
                // or touching the folder now checked out on a different branch.
                guard canPullWithoutEditingWorkspace(name, worktrees: try worktrees(at: path)),
                      try string(["rev-parse", "--verify", reference], at: path) == existing else {
                    throw GitError(message: "The selected branch or its workspace changed during fetch. Refresh before pulling.")
                }
                guard (try? run(["merge-base", "--is-ancestor", existing, fetched], at: path)) != nil else {
                    throw GitError(message: "Cannot fast-forward the selected local branch. Its history has diverged; no local branch or workspace was changed.")
                }
                // A non-forced local fetch also lets Git reject a branch checked out
                // in any worktree, including one opened since the snapshot above.
                _ = try run(["-c", "fetch.recurseSubmodules=false", "fetch", "--no-tags", "--no-prune", "--no-prune-tags", "--no-write-fetch-head", "--no-recurse-submodules", "--", ".", fetched + ":" + reference], at: path)
                output = "Updated origin/\(name) and local \(name). No workspace was changed."
                break
            }
            if existing == nil { _ = try createLocalBranchFromRemote("refs/remotes/origin/" + name, at: path) }
            let destination = try openLocalBranch(name, at: path)
            try validatePullWorkspace(destination.path, branch: reference)
            if let existing, try string(["rev-parse", "HEAD"], at: destination.path) != existing {
                throw GitError(message: "The selected branch changed during fetch. No merge was performed; refresh and try again.")
            }
            output = try string(["merge", "--ff-only", "--", fetched], at: destination.path)
        }
        return ActionResult(output: output, backup: nil)
    }
    public static func canPullWithoutEditingWorkspace(_ name: String, worktrees: [GitWorktree]) -> Bool {
        let reference = "refs/heads/" + name
        let assigned = worktrees.filter { $0.assignedBranch == reference || $0.branch == reference }
        guard assigned.count == 1, let tree = assigned.first else { return false }
        return tree.associationIssue != nil && tree.branch != nil && tree.branch != reference
    }
    /// Remotes first, so a remote that cannot be reached leaves the local tag in place for a retry.
    private static func deleteTagEverywhere(_ name: String, at path: String) throws -> String {
        let reference = "refs/tags/" + name
        _ = try run(["check-ref-format", reference], at: path)
        _ = try string(["show-ref", "--verify", "--hash", reference], at: path)
        let remotes = try string(["remote"], at: path).split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        var deleted: [String] = []
        for remote in remotes {
            do {
                let found = try string(["ls-remote", "--tags", "--refs", "--", remote, reference], at: path)
                guard !found.isEmpty else { continue }
                _ = try run(["-c", "push.followTags=false", "-c", "remote.\(remote).mirror=false", "-c", "push.recurseSubmodules=no", "push", "--porcelain", "--", remote, ":" + reference], at: path)
                deleted.append(remote)
            } catch {
                let done = deleted.isEmpty ? "" : " Already deleted on " + deleted.joined(separator: ", ") + "."
                throw GitError(message: "Could not delete the tag on \(remote).\(done) The local tag is kept.\n\n" + error.localizedDescription)
            }
        }
        _ = try run(["tag", "-d", "--", name], at: path)
        return deleted.isEmpty ? "Deleted locally. No remote had this tag." : "Deleted locally and on " + deleted.joined(separator: ", ") + "."
    }
    /// Never forced: a remote holding a different tag of the same name rejects the push and stops it.
    private static func pushTagEverywhere(_ name: String, at path: String) throws -> String {
        let reference = "refs/tags/" + name
        _ = try run(["check-ref-format", reference], at: path)
        let object = try string(["show-ref", "--verify", "--hash", reference], at: path)
        let remotes = try string(["remote"], at: path).split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        guard !remotes.isEmpty else { throw GitError(message: "Add a remote before pushing this tag.") }
        var pushed: [String] = []
        for remote in remotes {
            do {
                _ = try run(["-c", "push.followTags=false", "-c", "remote.\(remote).mirror=false", "-c", "push.recurseSubmodules=no", "push", "--porcelain", "--", remote, object + ":" + reference], at: path)
                pushed.append(remote)
            } catch {
                let done = pushed.isEmpty ? "" : " Already pushed to " + pushed.joined(separator: ", ") + "."
                throw GitError(message: "Could not push the tag to \(remote).\(done)\n\n" + error.localizedDescription)
            }
        }
        return "Pushed to " + pushed.joined(separator: ", ") + "."
    }
    private static func requireOrigin(at path: String) throws {
        guard (try? run(["remote", "get-url", "origin"], at: path)) != nil else {
            throw GitError(message: "Configure the origin remote before publishing or pulling this item.")
        }
    }
    private static func pushReference(_ reference: String, at path: String) throws -> String {
        try requireOrigin(at: path)
        // Resolve an immutable object now; never push all refs/tags or use force.
        let object = try string(["show-ref", "--verify", "--hash", reference], at: path)
        return try string(["-c", "push.followTags=false", "-c", "remote.origin.mirror=false", "-c", "push.recurseSubmodules=no", "push", "--porcelain", "--", "origin", object + ":" + reference], at: path)
    }
    private static func validatePullWorkspace(_ path: String, branch: String) throws {
        try validateWorkspace(at: path)
        guard try string(["symbolic-ref", "--quiet", "HEAD"], at: path) == branch else {
            throw GitError(message: "The selected branch's workspace changed outside the app. Refresh before pulling.")
        }
        guard try pendingOperation(at: path) == nil else { throw GitError(message: "Finish or abort the pending Git operation in the selected workspace first.") }
        guard try run(["status", "--porcelain=v1", "-z"], at: path).isEmpty else {
            throw GitError(message: "The selected branch's workspace has local changes. Commit or stash them before pulling.")
        }
    }
}
