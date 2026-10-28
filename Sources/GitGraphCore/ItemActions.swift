import Foundation

public enum RepositoryItemAction {
    case pushBranch(String), pullBranch(String), pushTag(String)
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
        case .pullBranch(let name):
            try validateBranch(name, at: path); try requireOrigin(at: path)
            let reference = "refs/heads/" + name
            let existing = try? string(["show-ref", "--verify", "--hash", reference], at: path)
            let trees = try worktrees(at: path)
            if let tree = trees.first(where: { $0.branch == reference || $0.assignedBranch == reference }) {
                try validatePullWorkspace(tree.path, branch: reference)
            }
            _ = try run(["-c", "fetch.recurseSubmodules=false", "fetch", "--no-tags", "--no-recurse-submodules", "--", "origin", "+refs/heads/" + name + ":refs/remotes/origin/" + name], at: path)
            let fetched = try string(["rev-parse", "--verify", "refs/remotes/origin/" + name + "^{commit}"], at: path)
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
