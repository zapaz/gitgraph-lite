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

    public static func automaticWorktree(at path: String, start: String = "HEAD", branch existingBranch: String? = nil) throws -> NavigationResult {
        let trees = try worktrees(at: path)
        var remoteStart: String?
        if let branch = existingBranch {
            try validateBranch(branch, at: path)
            if let tree = trees.first(where: { $0.branch == "refs/heads/" + branch }) {
                guard tree.exists && !tree.isBare else { throw GitError(message: "This branch's worktree is unavailable: \(tree.path)") }
                return NavigationResult(path: tree.path, branch: branch, didCreateWorktree: false, didCreateBranch: false)
            }
            if (try? run(["show-ref", "--verify", "refs/heads/" + branch], at: path)) == nil {
                let full = "refs/remotes/origin/" + branch
                guard try references(at: path).contains(where: { $0.name == full && !$0.symbolic }) else { throw GitError(message: "Branch is no longer available: " + branch) }
                remoteStart = full
            }
        }
        let commit = try string(["rev-parse", "--verify", "--end-of-options", (remoteStart ?? existingBranch.map { "refs/heads/" + $0 } ?? start) + "^{commit}"], at: path)
        let name: String
        if let existingBranch { name = existingBranch }
        else {
            let subject = try string(["show", "-s", "--format=%s", commit, "--"], at: path)
            let base = "worktree/" + String(folderSlug(subject).prefix(44)).lowercased() + "-" + commit.prefix(8)
            var candidate = base, suffix = 2
            while (try? run(["show-ref", "--verify", "refs/heads/" + candidate], at: path)) != nil { candidate = base + "-\(suffix)"; suffix += 1 }
            name = candidate
        }
        let root = URL(fileURLWithPath: trees.first(where: \.isMain)?.path ?? path)
        let baseFolder = root.deletingLastPathComponent().appendingPathComponent(root.lastPathComponent + "-worktrees", isDirectory: true)
        try FileManager.default.createDirectory(at: baseFolder, withIntermediateDirectories: true)
        let stem = folderSlug(name)
        var destination = baseFolder.appendingPathComponent(stem), suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) || trees.contains(where: { samePath($0.path, destination.path) }) {
            destination = baseFolder.appendingPathComponent(stem + "-\(suffix)"); suffix += 1
        }
        let source: WorktreeSource = (existingBranch == nil || remoteStart != nil) ? .newBranch(name: name, start: commit) : .existingBranch(name)
        _ = try performWorktree(.add(path: destination.path, source: source), at: path)
        if let remoteStart { _ = try run(["branch", "--set-upstream-to=" + remoteStart, "--", name], at: path) }
        return NavigationResult(path: destination.path, branch: name, didCreateWorktree: true, didCreateBranch: existingBranch == nil || remoteStart != nil)
    }

    public static func checkoutRemote(_ reference: String, at path: String, expectedSignature: String? = nil) throws -> NavigationResult {
        if let expectedSignature, try signature(at: path) != expectedSignature { throw GitError(message: "The repository changed. Refresh and try checkout again.") }
        if let pending = try pendingOperation(at: path) { throw GitError(message: "Finish or abort the pending \(pending) before checking out a remote branch.") }
        let fullName = reference.hasPrefix("refs/remotes/") ? reference : "refs/remotes/" + reference
        guard let ref = try references(at: path).first(where: { $0.name == fullName && !$0.symbolic }), ref.name.hasPrefix("refs/remotes/") else {
            throw GitError(message: "This remote branch is no longer available: \(reference)")
        }
        let short = String(fullName.dropFirst("refs/remotes/".count))
        // Remote names may themselves contain slashes: use the longest configured prefix.
        let remotes = try string(["remote"], at: path).components(separatedBy: "\n").filter { !$0.isEmpty }.sorted { $0.count > $1.count }
        guard let remote = remotes.first(where: { short.hasPrefix($0 + "/") }) else { throw GitError(message: "The remote for \(short) is not configured.") }
        let local = String(short.dropFirst(remote.count+1))
        try validateBranch(local, at: path)
        let trees = try parseWorktrees(worktreeMetadata(at: path))
        if let occupied = trees.first(where: { $0.branch == "refs/heads/" + local && !samePath($0.path, path) }) {
            throw GitError(message: "Local branch \(local) is already checked out in \(occupied.path). Git cannot check it out in two worktrees. No branch or files were changed.")
        }
        let exists = (try? run(["show-ref", "--verify", "refs/heads/" + local], at: path)) != nil
        let current = try? string(["symbolic-ref", "--quiet", "--short", "HEAD"], at: path)
        if current != local || !exists {
            guard (try run(["status", "--porcelain=v1", "-z"], at: path)).isEmpty else { throw GitError(message: "Commit or stash local changes before checkout. No files were changed.") }
            if exists { _ = try run(["switch", "--", local], at: path) }
            else { _ = try run(["switch", "--track", "-c", local, "--", fullName], at: path) }
        }
        // Preserve existing local commits and existing upstream configuration; never reset to the remote tip.
        let upstream = try string(["for-each-ref", "--format=%(upstream)", "refs/heads/" + local], at: path)
        if upstream.isEmpty { _ = try run(["branch", "--set-upstream-to=" + fullName, "--", local], at: path) }
        return NavigationResult(path: path, branch: local, didCreateWorktree: false, didCreateBranch: !exists)
    }
}
