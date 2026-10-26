import Foundation
import GitGraphCore

func checkWorktrees() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("GitGraphWorktreeChecks-" + UUID().uuidString)
    let main = folder.appendingPathComponent("main repo"), linked = folder.appendingPathComponent("linked é\nfolder")
    try FileManager.default.createDirectory(at: main, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    func git(_ args: [String], at path: String? = nil) throws -> String { try Git.string(args, at: path ?? main.path) }
    func expect(_ fragment: String, _ work: () throws -> Void) {
        do { try work(); preconditionFailure("Expected worktree failure: \(fragment)") }
        catch { precondition(error.localizedDescription.localizedCaseInsensitiveContains(fragment), "Unexpected error: \(error)") }
    }
    _ = try git(["init", "-b", "main"])
    _ = try git(["config", "user.name", "Worktree Checks"]); _ = try git(["config", "user.email", "worktree@example.invalid"])
    _ = try git(["config", "commit.gpgsign", "false"])
    let file = main.appendingPathComponent("file.txt")
    try "original\n".write(to: file, atomically: true, encoding: .utf8)
    _ = try git(["add", "."]); _ = try git(["commit", "-m", "Root"])
    let root = try git(["rev-parse", "HEAD"])
    let activeBranch = try git(["symbolic-ref", "HEAD"])
    let localNote = main.appendingPathComponent("local-note.txt")
    try "keep my edits\n".write(to: file, atomically: true, encoding: .utf8)
    try "keep my untracked file".write(to: localNote, atomically: true, encoding: .utf8)
    _ = try Git.performWorktree(.add(path: linked.path, source: .newBranch(name: "feature/worktree", start: root)), at: main.path)
    XCTAssertEqual(try git(["symbolic-ref", "HEAD"]), activeBranch)
    XCTAssertEqual(try git(["rev-parse", "HEAD"]), root)
    XCTAssertEqual(try String(contentsOf: file), "keep my edits\n")
    XCTAssertEqual(try String(contentsOf: localNote), "keep my untracked file")
    XCTAssertEqual(try String(contentsOf: linked.appendingPathComponent("file.txt")), "original\n")
    try "original\n".write(to: file, atomically: true, encoding: .utf8)
    try FileManager.default.removeItem(at: localNote)
    var trees = try Git.worktrees(at: main.path)
    XCTAssertEqual(trees.count, 2); XCTAssertTrue(trees[0].isMain)
    XCTAssertTrue(Git.samePath(trees[1].path, linked.path)); XCTAssertEqual(trees[1].branch, "refs/heads/feature/worktree")
    XCTAssertEqual(trees[1].changedFiles, 0)
    XCTAssertEqual(try Git.load(at: linked.path, branch: nil, limit: 500).branch, "feature/worktree")
    // Linked worktrees have a .git file, not a .git directory.
    var isDirectory: ObjCBool = false
    XCTAssertTrue(FileManager.default.fileExists(atPath: linked.appendingPathComponent(".git").path, isDirectory: &isDirectory))
    XCTAssertTrue(!isDirectory.boolValue)
    expect("already checked out") { _ = try Git.performWorktree(.add(path: folder.appendingPathComponent("duplicate").path, source: .existingBranch("feature/worktree")), at: main.path) }
    for action in [GitAction.renameBranch(old: "feature/worktree", new: "renamed"), .deleteBranch("feature/worktree")] {
        expect("checked out in worktree") { _ = try Git.perform(action, at: main.path) }
    }
    expect("checked out in worktree") { _ = try Git.perform(.renameBranch(old: "main", new: "renamed-main"), at: main.path) }
    expect("valid branch") { _ = try Git.performWorktree(.add(path: folder.appendingPathComponent("bad").path, source: .newBranch(name: "-bad", start: root)), at: main.path) }
    let fingerprint = Git.worktreeSummary(trees)
    let untracked = linked.appendingPathComponent("untracked.txt")
    try "keep this".write(to: untracked, atomically: true, encoding: .utf8)
    trees = try Git.worktrees(at: main.path)
    XCTAssertEqual(trees[1].changedFiles, 1)
    XCTAssertNotEqual(Git.worktreeSummary(trees), fingerprint)
    expect("local changes") { _ = try Git.performWorktree(.remove(linked.path), at: main.path) }
    XCTAssertEqual(try String(contentsOf: untracked), "keep this")
    try FileManager.default.removeItem(at: untracked)
    _ = try Git.performWorktree(.lock(path: linked.path, reason: "Portable disk\nkeep registered"), at: main.path)
    trees = try Git.worktrees(at: main.path)
    XCTAssertTrue(trees[1].isLocked); XCTAssertEqual(trees[1].lockReason, "Portable disk\nkeep registered")
    expect("Unlock") { _ = try Git.performWorktree(.remove(linked.path), at: main.path) }
    _ = try Git.performWorktree(.unlock(linked.path), at: main.path)
    expect("active worktree") { _ = try Git.performWorktree(.remove(linked.path), at: linked.path) }
    expect("main worktree") { _ = try Git.performWorktree(.remove(main.path), at: main.path) }
    let moved = folder.appendingPathComponent("moved worktree")
    _ = try Git.performWorktree(.move(path: linked.path, destination: moved.path), at: main.path)
    XCTAssertTrue(!FileManager.default.fileExists(atPath: linked.path))
    XCTAssertEqual(try Git.worktrees(at: moved.path).count, 2)
    _ = try Git.performWorktree(.remove(moved.path), at: main.path)
    XCTAssertEqual(try Git.worktrees(at: main.path).count, 1)
    XCTAssertTrue(try git(["branch", "--list", "feature/worktree"]).contains("feature/worktree"))
    let detached = folder.appendingPathComponent("detached")
    _ = try Git.performWorktree(.add(path: detached.path, source: .detached(root)), at: main.path)
    try "detached\n".write(to: detached.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
    _ = try git(["add", "."], at: detached.path); _ = try git(["commit", "-m", "Detached worktree commit"], at: detached.path)
    let detachedHead = try git(["rev-parse", "HEAD"], at: detached.path)
    XCTAssertTrue(try Git.load(at: main.path, branch: nil, limit: 500).commits.contains { $0.id == detachedHead })
    XCTAssertEqual(try Git.worktrees(at: main.path).last?.branch, nil)
    _ = try Git.performWorktree(.remove(detached.path), at: main.path)
    XCTAssertTrue(try Git.references(at: main.path).contains { $0.name.hasPrefix("refs/heads/gitgraph-backup/worktree-") && $0.target == detachedHead })
    let existing = folder.appendingPathComponent("existing branch worktree")
    try "local edits before opening another branch\n".write(to: file, atomically: true, encoding: .utf8)
    _ = try Git.performWorktree(.add(path: existing.path, source: .existingBranch("feature/worktree")), at: main.path)
    XCTAssertEqual(try git(["symbolic-ref", "HEAD"]), activeBranch)
    XCTAssertEqual(try git(["rev-parse", "HEAD"]), root)
    XCTAssertEqual(try String(contentsOf: file), "local edits before opening another branch\n")
    XCTAssertEqual(try Git.load(at: existing.path, branch: nil, limit: 500).branch, "feature/worktree")
    _ = try Git.performWorktree(.remove(existing.path), at: main.path)
    try "original\n".write(to: file, atomically: true, encoding: .utf8)
    XCTAssertEqual(try git(["status", "--porcelain"]), "")
    print("PASS: linked worktrees, new/existing branches, detached HEAD history, Unicode/newline paths, dirty/locked/main/active protections, move, remove and cross-worktree branch guards")
    print("PASS: new/existing-branch worktree creation preserves the active branch, HEAD, tracked edits and untracked files")
}
