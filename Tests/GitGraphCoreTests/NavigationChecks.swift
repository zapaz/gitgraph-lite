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
    func write(_ path: URL, _ text: String) throws { try text.write(to: path, atomically: true, encoding: .utf8) }
    func commit(_ message: String, at path: URL) throws { _ = try git(["add", "."], at: path); _ = try git(["commit", "-m", message], at: path) }
    func rejected(_ fragment: String, _ work: () throws -> Void) {
        do { try work(); preconditionFailure("Expected navigation failure: \(fragment)") }
        catch { precondition(error.localizedDescription.localizedCaseInsensitiveContains(fragment), "Unexpected navigation failure: \(error)") }
    }
    _ = try git(["init", "-b", "main"], at: seed); try configure(seed)
    try write(seed.appendingPathComponent("app.txt"), "main\n"); try commit("Initial application", at: seed)
    _ = try git(["switch", "-c", "feature/ui"], at: seed)
    try write(seed.appendingPathComponent("feature.txt"), "feature\n"); try commit("Feature UI", at: seed)
    _ = try git(["switch", "main"], at: seed)
    _ = try git(["branch", "topic/nested"], at: seed)
    _ = try git(["clone", "--bare", seed.path, origin.path], at: folder)
    _ = try git(["clone", origin.path, repo.path], at: folder); try configure(repo)
    _ = try git(["switch", "-c", "scratch"]); _ = try git(["branch", "-D", "main"])

    let fresh = try Git.checkoutRemote("origin/main", at: repo.path)
    XCTAssertEqual(fresh.branch, "main"); XCTAssertTrue(fresh.didCreateBranch); XCTAssertTrue(!fresh.didCreateWorktree)
    XCTAssertTrue(Git.samePath(fresh.path, repo.path))
    XCTAssertEqual(try git(["branch", "--show-current"]), "main")
    XCTAssertEqual(try git(["rev-parse", "--symbolic-full-name", "@{upstream}"]), "refs/remotes/origin/main")
    XCTAssertEqual(try Git.worktrees(at: repo.path).count, 1)
    try write(repo.appendingPathComponent("local.txt"), "local commit\n"); try commit("Local main ahead", at: repo)
    let ahead = try git(["rev-parse", "HEAD"])
    _ = try git(["switch", "scratch"])
    let existing = try Git.checkoutRemote("origin/main", at: repo.path)
    XCTAssertTrue(!existing.didCreateBranch); XCTAssertEqual(try git(["rev-parse", "HEAD"]), ahead)
    XCTAssertEqual(try String(contentsOf: repo.appendingPathComponent("local.txt")), "local commit\n")
    _ = try Git.checkoutRemote("refs/remotes/origin/feature/ui", at: repo.path)
    XCTAssertEqual(try git(["branch", "--show-current"]), "feature/ui")
    XCTAssertEqual(try git(["rev-parse", "--symbolic-full-name", "@{upstream}"]), "refs/remotes/origin/feature/ui")

    let before = try git(["rev-parse", "HEAD"])
    try write(repo.appendingPathComponent("app.txt"), "keep local edits\n")
    rejected("local changes") { _ = try Git.checkoutRemote("origin/main", at: repo.path) }
    XCTAssertEqual(try git(["branch", "--show-current"]), "feature/ui")
    XCTAssertEqual(try git(["rev-parse", "HEAD"]), before)
    XCTAssertEqual(try String(contentsOf: repo.appendingPathComponent("app.txt")), "keep local edits\n")
    try write(repo.appendingPathComponent("app.txt"), "main\n")
    let occupied = folder.appendingPathComponent("main-in-use")
    _ = try Git.performWorktree(.add(path: occupied.path, source: .existingBranch("main")), at: repo.path)
    rejected("already checked out") { _ = try Git.checkoutRemote("origin/main", at: repo.path) }
    XCTAssertEqual(try git(["branch", "--show-current"]), "feature/ui")
    _ = try Git.performWorktree(.remove(occupied.path), at: repo.path)
    rejected("no longer available") { _ = try Git.checkoutRemote("origin/HEAD", at: repo.path) }
    let signature = try Git.signature(at: repo.path)
    _ = try git(["tag", "state-changed"])
    rejected("repository changed") { _ = try Git.checkoutRemote("origin/main", at: repo.path, expectedSignature: signature) }

    _ = try git(["remote", "add", "team/upstream", origin.path]); _ = try git(["fetch", "team/upstream"])
    _ = try Git.checkoutRemote("team/upstream/topic/nested", at: repo.path)
    XCTAssertEqual(try git(["branch", "--show-current"]), "topic/nested")
    XCTAssertEqual(try git(["rev-parse", "--symbolic-full-name", "@{upstream}"]), "refs/remotes/team/upstream/topic/nested")
    print("PASS: remote checkout in the same worktree, exact local names, nested branches/remotes, tracking, preservation of local commits and dirty/occupied/stale guards")

    let currentHead = try git(["rev-parse", "HEAD"])
    try write(repo.appendingPathComponent("app.txt"), "unsaved tracked\n")
    try write(repo.appendingPathComponent("untracked.txt"), "unsaved untracked\n")
    let first = try Git.automaticWorktree(at: repo.path)
    XCTAssertTrue(first.didCreateWorktree && first.didCreateBranch)
    XCTAssertTrue(URL(fileURLWithPath: first.path).deletingLastPathComponent().lastPathComponent == "repository-worktrees")
    XCTAssertTrue(first.branch.hasPrefix("worktree/"))
    XCTAssertEqual(try git(["branch", "--show-current"]), "topic/nested")
    XCTAssertEqual(try git(["rev-parse", "HEAD"]), currentHead)
    XCTAssertEqual(try String(contentsOf: repo.appendingPathComponent("app.txt")), "unsaved tracked\n")
    XCTAssertEqual(try String(contentsOf: repo.appendingPathComponent("untracked.txt")), "unsaved untracked\n")
    XCTAssertEqual(try git(["branch", "--show-current"], at: URL(fileURLWithPath: first.path)), first.branch)
    let second = try Git.automaticWorktree(at: repo.path)
    XCTAssertNotEqual(first.path, second.path); XCTAssertNotEqual(first.branch, second.branch)
    let named = try Git.automaticWorktree(at: repo.path, branch: "main")
    XCTAssertTrue(named.didCreateWorktree && !named.didCreateBranch)
    let reused = try Git.automaticWorktree(at: repo.path, branch: "main")
    XCTAssertEqual(reused.path, named.path); XCTAssertTrue(!reused.didCreateWorktree)
    XCTAssertTrue(Git.samePath(try Git.automaticWorktree(at: repo.path, branch: "topic/nested").path, repo.path))
    _ = try git(["branch", "foo/bar"]); _ = try git(["branch", "foo-bar"])
    let collision1 = try Git.automaticWorktree(at: repo.path, branch: "foo/bar")
    let collision2 = try Git.automaticWorktree(at: repo.path, branch: "foo-bar")
    XCTAssertNotEqual(collision1.path, collision2.path)
    XCTAssertEqual(try String(contentsOf: repo.appendingPathComponent("app.txt")), "unsaved tracked\n")
    print("PASS: automatic worktree folders and branch names, collision avoidance, reuse, and preservation of the original worktree's HEAD and uncommitted files")

    let unborn = folder.appendingPathComponent("unborn")
    try FileManager.default.createDirectory(at: unborn, withIntermediateDirectories: true)
    _ = try git(["init", "-b", "main"], at: unborn)
    _ = try git(["remote", "add", "origin", origin.path], at: unborn); _ = try git(["fetch", "origin"], at: unborn)
    _ = try Git.checkoutRemote("origin/main", at: unborn.path)
    XCTAssertEqual(try git(["branch", "--show-current"], at: unborn), "main")
    XCTAssertEqual(try String(contentsOf: unborn.appendingPathComponent("app.txt")), "main\n")
    print("PASS: origin/main checkout when the current local main branch is unborn")
}
