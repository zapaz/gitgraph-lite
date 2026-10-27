import Foundation
import Darwin

private struct WorkspaceRecord: Codable {
    let branch: String
    var path: String
}

// Repository-private metadata: not tracked, pushed, or shared with another clone.
// The Git administration directory identifies a worktree even after it is moved.
public enum WorkspaceAssociations {
    private static func rebasing(_ branch: String, at path: String) throws -> Bool {
        guard try Git.pendingOperation(at: path) == "rebase" else { return false }
        for state in ["rebase-merge/head-name", "rebase-apply/head-name"] {
            let raw = try Git.string(["rev-parse", "--git-path", state], at: path)
            let file = URL(fileURLWithPath: raw, relativeTo: URL(fileURLWithPath: path, isDirectory: true))
            if let name = try? String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), name == branch { return true }
        }
        return false
    }

    public static func annotate(_ trees: [GitWorktree], at path: String) throws -> [GitWorktree] {
        let raw = try Git.string(["rev-parse", "--git-common-dir"], at: path)
        let common = URL(fileURLWithPath: raw, relativeTo: URL(fileURLWithPath: path, isDirectory: true)).standardizedFileURL.resolvingSymlinksInPath()
        let file = common.appendingPathComponent("gitgraph-lite-workspaces.json")
        let fd = Darwin.open(common.appendingPathComponent("gitgraph-lite-workspaces.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw GitError(message: "Cannot access this repository's workspace associations.") }
        defer { Darwin.close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw GitError(message: "Cannot lock workspace associations. Try again.") }
        defer { flock(fd, LOCK_UN) }
        var records: [String: WorkspaceRecord] = [:]
        if FileManager.default.fileExists(atPath: file.path) {
            do { records = try JSONDecoder().decode([String: WorkspaceRecord].self, from: Data(contentsOf: file)) }
            catch { throw GitError(message: "Workspace association metadata cannot be read: \(file.path). No association was changed.") }
        }
        let before = records
        var result: [GitWorktree] = []
        for var tree in trees {
            guard !tree.isBare else { result.append(tree); continue }
            let key: String?
            if tree.exists {
                let gitDir = try Git.string(["rev-parse", "--absolute-git-dir"], at: tree.path)
                let normalized = URL(fileURLWithPath: gitDir).standardizedFileURL.resolvingSymlinksInPath().path
                if normalized == common.path { key = "main" }
                else if normalized.hasPrefix(common.path + "/worktrees/") { key = String(normalized.dropFirst(common.path.count+1)) }
                else { tree.associationIssue = "Worktree belongs to a different repository."; result.append(tree); continue }
            } else { key = records.first { Git.samePath($0.value.path, tree.path) }?.key }
            if let key {
                if records[key] == nil, let branch = tree.branch { records[key] = WorkspaceRecord(branch: branch, path: tree.path) }
                if var record = records[key] {
                    record.path = tree.path; records[key] = record; tree.assignedBranch = record.branch
                    if tree.exists && tree.branch != record.branch {
                        let transient = tree.branch == nil ? try rebasing(record.branch, at: tree.path) : false
                        if !transient {
                            tree.associationIssue = "Expected \(String(record.branch.dropFirst(11))), currently \(tree.branchLabel). Changed outside the app; restore the expected branch in your Git tool before editing here."
                        }
                    }
                }
            }
            result.append(tree)
        }
        // Removing a workspace ends that directory's lifetime; the branch itself remains independent.
        // Use Git's live administration directories rather than this caller's possibly older snapshot.
        // Another app instance may have added a worktree while this one waited for the lock.
        records = records.filter { key, _ in key == "main" || FileManager.default.fileExists(atPath: common.appendingPathComponent(key).path) }
        for i in result.indices {
            if let assigned = result[i].assignedBranch,
               result.indices.contains(where: { $0 != i && (result[$0].assignedBranch == assigned || result[$0].branch == assigned) }) {
                result[i].associationIssue = "This branch is associated with more than one registered worktree. Inspect the worktrees before editing."
            }
        }
        let changed = records.count != before.count || records.contains { key, value in before[key]?.branch != value.branch || before[key]?.path != value.path }
        if changed {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(records).write(to: file, options: .atomic)
        }
        return result
    }
}

extension Git {
    public static func validateWorkspace(at path: String) throws {
        let trees = try worktrees(at: path)
        guard let active = trees.first(where: { samePath($0.path, path) }) else { throw GitError(message: "The current folder is no longer a registered worktree.") }
        if let issue = active.associationIssue { throw GitError(message: issue) }
        guard active.assignedBranch != nil else { throw GitError(message: "This detached workspace is unmanaged. Create a local branch and open its dedicated workspace before editing here.") }
    }
}
