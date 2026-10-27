import Foundation

public struct NavigationResult {
    public let path: String
    public let branch: String
    public let didCreateWorktree: Bool
    public let didCreateBranch: Bool
}

extension Git {
    private static func folderSlug(_ text: String) -> String {
        let slug = text.replacingOccurrences(of: "[^A-Za-z0-9._-]+", with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        return String((slug.isEmpty ? "worktree" : slug).prefix(80))
    }
    private static func validateNavigationSignature(_ expected: String?, at path: String) throws {
        if let expected, try signature(at: path) != expected { throw GitError(message: "The repository changed. Refresh and try again.") }
    }
    private static func availableBranchName(at path: String, start: String) throws -> String {
        let subject = try string(["show", "-s", "--format=%s", start, "--"], at: path)
        let base = "worktree/" + String(folderSlug(subject).prefix(44)).lowercased() + "-" + start.prefix(8)
        let reserved = Set(try worktrees(at: path).compactMap(\.assignedBranch))
        var candidate = base, suffix = 2
        while reserved.contains("refs/heads/" + candidate) || (try? run(["show-ref", "--verify", "refs/heads/" + candidate], at: path)) != nil {
            candidate = base + "-\(suffix)"; suffix += 1
        }
        return candidate
    }
    // Creates a ref only: no folder, checkout or worktree is created.
    @discardableResult public static func createLocalBranch(at path: String, start: String = "HEAD", name: String? = nil, expectedSignature: String? = nil) throws -> String {
        try validateNavigationSignature(expectedSignature, at: path)
        let commit = try string(["rev-parse", "--verify", "--end-of-options", start + "^{commit}"], at: path)
        let branch = try name ?? availableBranchName(at: path, start: commit)
        try validateBranch(branch, at: path)
        guard !(try worktrees(at: path)).contains(where: { $0.assignedBranch == "refs/heads/" + branch }) else { throw GitError(message: "This branch name is already assigned to a worktree: " + branch) }
        _ = try run(["branch", "--", branch, commit], at: path)
        return branch
    }
    private static func remoteIdentity(_ reference: String, at path: String) throws -> (full: String, local: String) {
        let full = reference.hasPrefix("refs/remotes/") ? reference : "refs/remotes/" + reference
        guard try references(at: path).contains(where: { $0.name == full && !$0.symbolic }) else { throw GitError(message: "This remote branch is no longer available: " + reference) }
        let short = String(full.dropFirst("refs/remotes/".count))
        let remotes = try string(["remote"], at: path).split(separator: "\n").map(String.init).sorted { $0.count > $1.count }
        guard let remote = remotes.first(where: { short.hasPrefix($0 + "/") }) else { throw GitError(message: "The remote for \(short) is not configured.") }
        let local = String(short.dropFirst(remote.count+1)); try validateBranch(local, at: path)
        return (full, local)
    }
    // Materializing a remote branch locally is independent of opening its workspace.
    @discardableResult public static func createLocalBranchFromRemote(_ reference: String, at path: String, expectedSignature: String? = nil) throws -> String {
        try validateNavigationSignature(expectedSignature, at: path)
        let remote = try remoteIdentity(reference, at: path)
        let exists = (try? run(["show-ref", "--verify", "refs/heads/" + remote.local], at: path)) != nil
        if exists {
            let upstream = try string(["for-each-ref", "--format=%(upstream)", "refs/heads/" + remote.local], at: path)
            guard upstream.isEmpty || upstream == remote.full else { throw GitError(message: "Local branch \(remote.local) already tracks \(upstream). Open that local branch explicitly; its tracking was not changed.") }
            if upstream.isEmpty { _ = try run(["branch", "--set-upstream-to=" + remote.full, "--", remote.local], at: path) }
        } else {
            guard !(try worktrees(at: path)).contains(where: { $0.assignedBranch == "refs/heads/" + remote.local || $0.branch == "refs/heads/" + remote.local }) else {
                throw GitError(message: "Branch \(remote.local) is already assigned to an unborn or unavailable worktree. No files or HEAD were changed.")
            }
            _ = try run(["branch", "--track", "--", remote.local, remote.full], at: path)
        }
        return remote.local
    }
    public static func openLocalBranch(_ branch: String, at path: String, expectedSignature: String? = nil) throws -> NavigationResult {
        try validateNavigationSignature(expectedSignature, at: path)
        try validateBranch(branch, at: path)
        let trees = try worktrees(at: path), full = "refs/heads/" + branch
        let assigned = trees.filter { $0.assignedBranch == full || $0.branch == full }
        if let tree = assigned.first {
            guard assigned.count == 1 else { throw GitError(message: "This branch has more than one registered worktree. Inspect them before opening.") }
            guard tree.exists && !tree.isBare else { throw GitError(message: "This branch's worktree is unavailable: " + tree.path) }
            if let issue = tree.associationIssue { throw GitError(message: issue) }
            return NavigationResult(path: tree.path, branch: branch, didCreateWorktree: false, didCreateBranch: false)
        }
        _ = try run(["show-ref", "--verify", full], at: path)
        let root = URL(fileURLWithPath: trees.first(where: \.isMain)?.path ?? path)
        let base = root.deletingLastPathComponent().appendingPathComponent(root.lastPathComponent + "-worktrees", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let stem = folderSlug(branch)
        var destination = base.appendingPathComponent(stem), suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) || trees.contains(where: { samePath($0.path, destination.path) }) {
            destination = base.appendingPathComponent(stem + "-\(suffix)"); suffix += 1
        }
        _ = try performWorktree(.add(path: destination.path, source: .existingBranch(branch)), at: path)
        return NavigationResult(path: destination.path, branch: branch, didCreateWorktree: true, didCreateBranch: false)
    }
    public static func openRemoteBranch(_ reference: String, at path: String, expectedSignature: String? = nil) throws -> NavigationResult {
        try validateNavigationSignature(expectedSignature, at: path)
        let remote = try remoteIdentity(reference, at: path)
        let existed = (try? run(["show-ref", "--verify", "refs/heads/" + remote.local], at: path)) != nil
        // Check existing associations before changing tracking configuration.
        for tree in try worktrees(at: path) where tree.assignedBranch == "refs/heads/" + remote.local || tree.branch == "refs/heads/" + remote.local {
            if let issue = tree.associationIssue { throw GitError(message: issue) }
            guard tree.exists else { throw GitError(message: "This branch's worktree is unavailable: " + tree.path) }
        }
        let local = try createLocalBranchFromRemote(reference, at: path)
        let result = try openLocalBranch(local, at: path)
        return NavigationResult(path: result.path, branch: local, didCreateWorktree: result.didCreateWorktree, didCreateBranch: !existed)
    }
    public static func automaticWorktree(at path: String, start: String = "HEAD", branch: String? = nil) throws -> NavigationResult {
        if let branch {
            if (try? run(["show-ref", "--verify", "refs/heads/" + branch], at: path)) != nil { return try openLocalBranch(branch, at: path) }
            return try openRemoteBranch("origin/" + branch, at: path)
        }
        let local = try createLocalBranch(at: path, start: start)
        let result = try openLocalBranch(local, at: path)
        return NavigationResult(path: result.path, branch: local, didCreateWorktree: result.didCreateWorktree, didCreateBranch: true)
    }
}
