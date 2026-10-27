import Foundation
import GitGraphCore

func checkAutomaticNavigation() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("GitGraphNavigation-" + UUID().uuidString)
    let seed = folder.appendingPathComponent("seed"), origin = folder.appendingPathComponent("origin.git"), repo = folder.appendingPathComponent("repository")
    try FileManager.default.createDirectory(at: seed, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    func git(_ args: [String], at path: URL? = nil) throws -> String { try Git.string(args, at: (path ?? repo).path) }
    func configure(_ path: URL) throws {
        for (key, value) in [("user.name", "Navigation Checks"), ("user.email", "navigation@example.invalid"), ("commit.gpgsign", "false"), ("core.hooksPath", "/dev/null")] { _ = try git(["config", key, value], at: path) }
    }
    func commit(_ message: String, at path: URL) throws { _ = try git(["add", "."], at: path); _ = try git(["commit", "--allow-empty", "-m", message], at: path) }
    func rejected(_ fragment: String, _ work: () throws -> Void) {
        do { try work(); preconditionFailure("Expected failure: \(fragment)") }
        catch { precondition(error.localizedDescription.localizedCaseInsensitiveContains(fragment), "Unexpected failure: \(error)") }
    }
    _ = try git(["init", "-b", "main"], at: seed); try configure(seed)
    try "main\n".write(to: seed.appendingPathComponent("app.txt"), atomically: true, encoding: .utf8)
    try commit("Initial application", at: seed)
    _ = try git(["switch", "-c", "feature/ui"], at: seed)
    try "feature\n".write(to: seed.appendingPathComponent("feature.txt"), atomically: true, encoding: .utf8)
    try commit("Feature UI", at: seed)
    _ = try git(["switch", "main"], at: seed); _ = try git(["branch", "topic/nested"], at: seed)
    _ = try git(["clone", "--bare", seed.path, origin.path], at: folder)
    _ = try git(["clone", origin.path, repo.path], at: folder); try configure(repo)
    let root = try git(["rev-parse", "HEAD"])
    _ = try Git.load(at: repo.path, branch: nil, limit: 500)
    let local = try Git.createLocalBranch(at: repo.path, name: "planning/local")
    XCTAssertEqual(local, "planning/local")
    let generated = try Git.createLocalBranch(at: repo.path)
    XCTAssertTrue(generated.hasPrefix("worktree/"))
    XCTAssertEqual(try Git.worktrees(at: repo.path).count, 1)
    XCTAssertTrue(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("repository-worktrees").path))
    let remoteLocal = try Git.createLocalBranchFromRemote("origin/feature/ui", at: repo.path)
    XCTAssertEqual(remoteLocal, "feature/ui")
    XCTAssertEqual(try git(["for-each-ref", "--format=%(upstream)", "refs/heads/feature/ui"]), "refs/remotes/origin/feature/ui")
    XCTAssertEqual(try Git.worktrees(at: repo.path).count, 1)
    // Viewing and filtering never creates worktrees.
    _ = try Git.load(at: repo.path, branchNames: ["feature/ui"], pins: [], limit: 500)
    XCTAssertEqual(try Git.worktrees(at: repo.path).count, 1)
    XCTAssertEqual(try git(["symbolic-ref", "--short", "HEAD"]), "main")
    XCTAssertEqual(try git(["rev-parse", "HEAD"]), root)
    print("PASS: local and tracking branch creation without worktrees; history consultation and filtering remain independent")

    try "unsaved tracked\n".write(to: repo.appendingPathComponent("app.txt"), atomically: true, encoding: .utf8)
    try "unsaved untracked\n".write(to: repo.appendingPathComponent("untracked.txt"), atomically: true, encoding: .utf8)
    let opened = try Git.openLocalBranch("feature/ui", at: repo.path)
    let feature = URL(fileURLWithPath: opened.path)
    XCTAssertTrue(opened.didCreateWorktree && !opened.didCreateBranch)
    XCTAssertEqual(try git(["symbolic-ref", "--short", "HEAD"], at: feature), "feature/ui")
    XCTAssertEqual(try git(["symbolic-ref", "--short", "HEAD"]), "main")
    XCTAssertEqual(try git(["rev-parse", "HEAD"]), root)
    XCTAssertEqual(try String(contentsOf: repo.appendingPathComponent("app.txt"), encoding: .utf8), "unsaved tracked\n")
    XCTAssertEqual(try String(contentsOf: repo.appendingPathComponent("untracked.txt"), encoding: .utf8), "unsaved untracked\n")
    XCTAssertEqual(try Git.openLocalBranch("feature/ui", at: repo.path).path, feature.path)
    XCTAssertEqual(try Git.openRemoteBranch("origin/feature/ui", at: repo.path).path, feature.path)
    XCTAssertTrue(Git.samePath(try Git.openLocalBranch("main", at: feature.path).path, repo.path))
    XCTAssertEqual(try Git.worktrees(at: repo.path).count, 2)
    let nested = try Git.openRemoteBranch("origin/topic/nested", at: repo.path)
    XCTAssertTrue(nested.didCreateWorktree && nested.didCreateBranch)
    XCTAssertEqual(try Git.string(["rev-parse", "--symbolic-full-name", "@{upstream}"], at: nested.path), "refs/remotes/origin/topic/nested")
    XCTAssertEqual(try git(["symbolic-ref", "--short", "HEAD"]), "main")
    print("PASS: lazy dedicated worktrees, exactly one per branch, reuse from any worktree, remote opening and preservation of dirty current files/HEAD")

    try "main\n".write(to: repo.appendingPathComponent("app.txt"), atomically: true, encoding: .utf8)
    try FileManager.default.removeItem(at: repo.appendingPathComponent("untracked.txt"))
    try commit("Local main ahead", at: repo)
    let ahead = try git(["rev-parse", "HEAD"])
    XCTAssertTrue(Git.samePath(try Git.openRemoteBranch("origin/main", at: feature.path).path, repo.path))
    XCTAssertEqual(try git(["rev-parse", "HEAD"]), ahead)
    _ = try git(["remote", "add", "team/upstream", origin.path]); _ = try git(["fetch", "team/upstream"])
    rejected("already tracks") { _ = try Git.openRemoteBranch("team/upstream/main", at: repo.path) }
    _ = try git(["update-ref", "refs/remotes/team/upstream/future/nested", root])
    let other = try Git.openRemoteBranch("team/upstream/future/nested", at: repo.path)
    XCTAssertEqual(other.branch, "future/nested")
    XCTAssertEqual(try Git.string(["rev-parse", "--symbolic-full-name", "@{upstream}"], at: other.path), "refs/remotes/team/upstream/future/nested")
    rejected("no longer available") { _ = try Git.openRemoteBranch("origin/HEAD", at: repo.path) }
    let stale = try Git.signature(at: repo.path); _ = try git(["tag", "changed"])
    rejected("repository changed") { _ = try Git.openLocalBranch("main", at: repo.path, expectedSignature: stale) }
    print("PASS: local commits and upstreams preserved; nested remote names, symbolic refs and stale navigation guarded")

    _ = try Git.performWorktree(.remove(feature.path), at: repo.path)
    XCTAssertEqual(try git(["rev-parse", "refs/heads/feature/ui"]), try git(["rev-parse", "refs/remotes/origin/feature/ui"]))
    let restored = try Git.openLocalBranch("feature/ui", at: repo.path)
    XCTAssertTrue(restored.didCreateWorktree && !restored.didCreateBranch)
    let moved = folder.appendingPathComponent("feature-moved")
    _ = try Git.performWorktree(.move(path: restored.path, destination: moved.path), at: repo.path)
    XCTAssertTrue(Git.samePath(try Git.openLocalBranch("feature/ui", at: repo.path).path, moved.path))
    _ = try Git.createLocalBranch(at: repo.path, name: "external-change")
    _ = try git(["switch", "external-change"], at: moved) // An external Git tool, never the app.
    let altered = try Git.worktrees(at: repo.path).first { Git.samePath($0.path, moved.path) }!
    XCTAssertEqual(altered.assignedBranch, "refs/heads/feature/ui"); XCTAssertTrue(altered.associationIssue != nil)
    rejected("Expected feature/ui") { _ = try Git.openLocalBranch("feature/ui", at: repo.path) }
    rejected("Expected feature/ui") { _ = try Git.openLocalBranch("external-change", at: repo.path) }
    rejected("Expected feature/ui") { _ = try Git.perform(.reset(commit: root, mode: "soft"), at: moved.path, expectedSignature: Git.signature(at: moved.path)) }
    _ = try git(["switch", "feature/ui"], at: moved)
    XCTAssertTrue(try Git.worktrees(at: repo.path).first { Git.samePath($0.path, moved.path) }!.associationIssue == nil)
    let duplicate = folder.appendingPathComponent("forced-duplicate")
    _ = try git(["worktree", "add", "--force", duplicate.path, "feature/ui"])
    rejected("more than one") { _ = try Git.openLocalBranch("feature/ui", at: repo.path) }
    _ = try git(["worktree", "remove", duplicate.path])
    XCTAssertTrue(Git.samePath(try Git.openLocalBranch("feature/ui", at: repo.path).path, moved.path))
    // A temporary detached HEAD during rebase must not reassign the workspace.
    _ = try git(["checkout", "--detach"], at: moved)
    let gitDir = URL(fileURLWithPath: try git(["rev-parse", "--absolute-git-dir"], at: moved))
    let rebase = gitDir.appendingPathComponent("rebase-merge")
    try FileManager.default.createDirectory(at: rebase, withIntermediateDirectories: true)
    try "refs/heads/feature/ui\n".write(to: rebase.appendingPathComponent("head-name"), atomically: true, encoding: .utf8)
    XCTAssertTrue(Git.samePath(try Git.openLocalBranch("feature/ui", at: repo.path).path, moved.path))
    try FileManager.default.removeItem(at: rebase)
    XCTAssertTrue(try Git.worktrees(at: repo.path).first { Git.samePath($0.path, moved.path) }!.associationIssue != nil)
    _ = try git(["switch", "feature/ui"], at: moved)
    print("PASS: archiving preserves branches, lazy reactivation, stable associations after moves, external switch/duplicate detection and transient rebase handling")

    let clone = folder.appendingPathComponent("another-repository")
    _ = try git(["clone", origin.path, clone.path], at: folder)
    _ = try Git.createLocalBranch(at: clone.path, name: "planning/local")
    XCTAssertTrue(Git.samePath(try Git.openLocalBranch("main", at: clone.path).path, clone.path))
    XCTAssertTrue(Git.samePath(try Git.openLocalBranch("main", at: repo.path).path, repo.path))
    XCTAssertEqual(try Git.worktrees(at: clone.path).count, 1)
    let unborn = folder.appendingPathComponent("unborn")
    try FileManager.default.createDirectory(at: unborn, withIntermediateDirectories: true)
    _ = try git(["init", "-b", "main"], at: unborn)
    _ = try git(["remote", "add", "origin", origin.path], at: unborn); _ = try git(["fetch", "origin"], at: unborn)
    rejected("unborn") { _ = try Git.openRemoteBranch("origin/main", at: unborn.path) }
    XCTAssertEqual(try git(["symbolic-ref", "--short", "HEAD"], at: unborn), "main")
    XCTAssertTrue((try? git(["rev-parse", "--verify", "HEAD"], at: unborn)) == nil)
    print("PASS: associations scoped per clone, same branch names in independent repositories, and protection of an unborn main worktree")
}

func checkDedicatedWorkspaceRebase() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GitGraphDedicatedRebase-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    func git(_ args: [String], at path: String? = nil) throws -> String { try Git.string(["-c", "user.name=Rebase Checks", "-c", "user.email=rebase@example.invalid", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null"] + args, at: path ?? root.path) }
    _ = try git(["init", "-b", "main"])
    for (key, value) in [("user.name", "Rebase Checks"), ("user.email", "rebase@example.invalid"), ("commit.gpgsign", "false"), ("core.hooksPath", "/dev/null")] { _ = try git(["config", key, value]) }
    let file = root.appendingPathComponent("app.txt")
    try "root\n".write(to: file, atomically: true, encoding: .utf8)
    _ = try git(["add", "."]); _ = try git(["commit", "-m", "root"])
    _ = try Git.createLocalBranch(at: root.path, name: "topic")
    let topic = try Git.openLocalBranch("topic", at: root.path)
    try "main\n".write(to: file, atomically: true, encoding: .utf8)
    _ = try git(["commit", "-am", "main change"])
    try "topic\n".write(to: URL(fileURLWithPath: topic.path).appendingPathComponent("app.txt"), atomically: true, encoding: .utf8)
    _ = try git(["commit", "-am", "topic change"], at: topic.path)
    let original = try git(["rev-parse", "HEAD"], at: topic.path)
    do {
        _ = try Git.perform(.rebase("refs/heads/main"), at: topic.path, expectedSignature: Git.signature(at: topic.path))
        preconditionFailure("Expected rebase conflict")
    } catch { XCTAssertEqual(try Git.pendingOperation(at: topic.path), "rebase") }
    let during = try Git.worktrees(at: root.path).first { Git.samePath($0.path, topic.path) }!
    XCTAssertEqual(during.assignedBranch, "refs/heads/topic")
    XCTAssertTrue(during.associationIssue == nil)
    _ = try Git.perform(.abortOperation("rebase"), at: topic.path, expectedSignature: Git.signature(at: topic.path))
    XCTAssertEqual(try git(["symbolic-ref", "--short", "HEAD"], at: topic.path), "topic")
    XCTAssertEqual(try git(["rev-parse", "HEAD"], at: topic.path), original)
    XCTAssertEqual(try git(["symbolic-ref", "--short", "HEAD"]), "main")
    print("PASS: actual rebase conflicts retain the workspace's branch assignment and signature-guarded abort restores its original HEAD")
}
