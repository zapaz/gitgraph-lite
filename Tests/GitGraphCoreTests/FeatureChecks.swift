import Foundation
import GitGraphCore

private final class Fixture {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("GitGraphActions-" + UUID().uuidString)
    var path: String { url.path }
    init() throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        _ = try git(["init", "-b", "main"])
        for (name, value) in [("user.name", "GitGraph Checks"), ("user.email", "checks@example.invalid"), ("commit.gpgsign", "false"), ("tag.gpgsign", "false"), ("core.hooksPath", "/dev/null")] { _ = try git(["config", name, value]) }
        try write("shared.txt", "original\n")
        _ = try commit("Root")
    }
    deinit { try? FileManager.default.removeItem(at: url) }
    func git(_ args: [String]) throws -> String { try Git.string(args, at: path) }
    func write(_ name: String, _ contents: String) throws { try contents.write(to: url.appendingPathComponent(name), atomically: true, encoding: .utf8) }
    func commit(_ message: String) throws -> String {
        _ = try git(["add", "."]); _ = try git(["commit", "-m", message]); return try git(["rev-parse", "HEAD"])
    }
    @discardableResult func perform(_ action: GitAction) throws -> ActionResult { try Git.perform(action, at: path) }
}

private func expectFailure(_ fragment: String, _ action: () throws -> Void) {
    do { try action(); preconditionFailure("Expected failure: \(fragment)") }
    catch { precondition(error.localizedDescription.localizedCaseInsensitiveContains(fragment), "Unexpected error: \(error)") }
}

func checkVisualDiff() {
    let patch = """
    diff --git a/example b/example
    --- a/example
    +++ b/example
    @@ -8,4 +8,5 @@ example
     unchanged
    -let label = "old 🐱"
    -removed
    +let label = "new 🐶"
    +added
    +extra
     tail
    @@ -40 +41 @@
    -last
    +final
    \\ No newline at end of file

    """
    let diff = VisualDiff.parse(patch)
    XCTAssertEqual(diff.additions, 4); XCTAssertEqual(diff.deletions, 3)
    XCTAssertEqual(diff.changeStarts.count, 2)
    let changed = diff.rows[diff.changeStarts[0]]
    XCTAssertEqual(changed.oldNumber, 9); XCTAssertEqual(changed.newNumber, 9)
    XCTAssertEqual(changed.oldText, "let label = \"old 🐱\"")
    XCTAssertTrue(changed.oldHighlight != nil && changed.newHighlight != nil)
    XCTAssertEqual(diff.rows[diff.changeStarts[0]+2].oldText, nil)
    XCTAssertEqual(diff.rows[diff.changeStarts[0]+2].newText, "extra")
    XCTAssertEqual(diff.rows[diff.changeStarts[1]].oldNumber, 40)
    XCTAssertEqual(diff.rows[diff.changeStarts[1]].newNumber, 41)
    let ranges = VisualDiff.highlights("é🐱x", "é🐶x")
    XCTAssertEqual(ranges.0, NSRange(location: 1, length: 2))
    XCTAssertEqual(VisualDiff.highlights("same", "same").0, nil)
    XCTAssertTrue(VisualDiff.parse("Binary files a/a and b/a differ").isBinary)
    XCTAssertTrue(VisualDiff.parse("").rows.isEmpty)
    let crlf = VisualDiff.parse("@@ -1 +1 @@\n-before\r\n+after\r\n")
    XCTAssertEqual(crlf.rows.last?.newText, "after\r")
    print("PASS: aligned visual diffs, line numbers, unequal replacements, multiple hunks, Unicode highlights, CRLF and binary files")
}

func checkCommitActions() throws {
    let f = try Fixture(), root = try f.git(["rev-parse", "HEAD"])
    try f.perform(.createBranch(name: "feature", commit: root, checkout: true))
    try f.write("feature.txt", "feature\n"); let feature = try f.commit("Feature")
    try f.perform(.addTag(name: "annotated", commit: feature, message: "Release note"))
    let refs = try Git.references(at: f.path)
    XCTAssertEqual(refs.first { $0.shortName == "annotated" }?.target, feature)
    try f.perform(.deleteTag("annotated"))
    try f.perform(.addTag(name: "light", commit: root, message: ""))
    try f.perform(.deleteTag("light"))
    try f.perform(.checkoutBranch("main"))
    try f.write("main.txt", "main\n"); _ = try f.commit("Main change")
    try f.perform(.merge(commit: feature, noFastForward: true, squash: false))
    let merge = try f.git(["rev-parse", "HEAD"])
    XCTAssertEqual(try f.git(["show", "-s", "--format=%P", "HEAD"]).split(separator: " ").count, 2)
    try f.perform(.revert(commit: merge, mainline: 1))
    XCTAssertTrue(!FileManager.default.fileExists(atPath: f.url.appendingPathComponent("feature.txt").path))
    try f.perform(.createBranch(name: "pick", commit: root, checkout: true))
    try f.perform(.cherryPick(commit: feature, mainline: nil))
    XCTAssertTrue(FileManager.default.fileExists(atPath: f.url.appendingPathComponent("feature.txt").path))
    let picked = try f.git(["rev-parse", "HEAD"])
    try f.perform(.revert(commit: picked, mainline: nil))
    try f.perform(.renameBranch(old: "pick", new: "picked"))
    XCTAssertEqual(try f.git(["branch", "--show-current"]), "picked")
    try f.perform(.checkoutBranch("main"))
    expectFailure("not fully merged") { try f.perform(.deleteBranch("picked")) }
    try f.perform(.createBranch(name: "temporary", commit: root, checkout: false))
    try f.perform(.deleteBranch("temporary"))
    try f.perform(.checkoutCommit(root))
    XCTAssertEqual(try Git.load(at: f.path, branch: nil, limit: 500).branch, "Detached HEAD")
    expectFailure("local branch") { try f.perform(.rebase(feature)) }
    try f.perform(.checkoutBranch("main"))
    let signature = try Git.signature(at: f.path)
    try f.perform(.addTag(name: "changed", commit: root, message: ""))
    expectFailure("repository changed") { _ = try Git.perform(.checkoutCommit(root), at: f.path, expectedSignature: signature) }
    try f.write("untracked.txt", "keep me")
    expectFailure("clean working tree") { try f.perform(.checkoutCommit(root)) }
    XCTAssertEqual(try String(contentsOf: f.url.appendingPathComponent("untracked.txt")), "keep me")
    expectFailure("valid branch") { try f.perform(.createBranch(name: "-bad", commit: root, checkout: false)) }
    print("PASS: branch/tag creation, checkout, rename, safe deletion, cherry-pick, merge/revert, annotated tags, dirty/stale repository guards")
}

func checkHistoryRewrites() throws {
    let f = try Fixture(), root = try f.git(["rev-parse", "HEAD"])
    try f.write("a.txt", "a\n"); let a = try f.commit("A")
    try f.write("b.txt", "b\n"); let b = try f.commit("B")
    let dropped = try f.perform(.drop(a))
    XCTAssertTrue(!FileManager.default.fileExists(atPath: f.url.appendingPathComponent("a.txt").path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: f.url.appendingPathComponent("b.txt").path))
    XCTAssertEqual(try f.git(["rev-parse", try XCTUnwrap(dropped.backup)]), b)
    expectFailure("one parent") { try f.perform(.drop(root)) }
    let before = try f.git(["rev-parse", "HEAD"])
    let soft = try f.perform(.reset(commit: root, mode: "soft"))
    XCTAssertEqual(try f.git(["rev-parse", try XCTUnwrap(soft.backup)]), before)
    XCTAssertTrue(try f.git(["diff", "--cached", "--name-only"]).contains("b.txt"))
    try f.perform(.reset(commit: root, mode: "mixed"))
    XCTAssertEqual(try f.git(["diff", "--cached", "--name-only"]), "")
    // Restore tracked content before exercising hard reset.
    _ = try f.git(["add", "."]); _ = try f.git(["commit", "-m", "Restore B"])
    try f.write("b.txt", "unsaved\n")
    let hard = try f.perform(.reset(commit: root, mode: "hard"))
    XCTAssertTrue(hard.backup != nil)
    XCTAssertEqual(try f.git(["status", "--porcelain"]), "")
    XCTAssertTrue(!FileManager.default.fileExists(atPath: f.url.appendingPathComponent("b.txt").path))
    try f.perform(.createBranch(name: "topic", commit: root, checkout: true))
    try f.write("topic.txt", "topic\n"); _ = try f.commit("Topic")
    try f.perform(.checkoutBranch("main"))
    try f.write("main.txt", "main\n"); let main = try f.commit("Main")
    try f.perform(.checkoutBranch("topic"))
    let rebase = try f.perform(.rebase(main))
    XCTAssertTrue(rebase.backup != nil)
    XCTAssertEqual(try f.git(["rev-parse", "HEAD^"]), main)
    XCTAssertTrue(FileManager.default.fileExists(atPath: f.url.appendingPathComponent("topic.txt").path))
    print("PASS: drop, rebase, soft/mixed/hard reset and recoverable backup branches")
}

func checkConflicts() throws {
    let f = try Fixture(), root = try f.git(["rev-parse", "HEAD"])
    try f.perform(.createBranch(name: "conflicting", commit: root, checkout: true))
    try f.write("shared.txt", "feature\n"); let feature = try f.commit("Feature edit")
    try f.perform(.checkoutBranch("main"))
    try f.write("shared.txt", "main\n"); let main = try f.commit("Main edit")
    expectFailure("in progress") { try f.perform(.cherryPick(commit: feature, mainline: nil)) }
    XCTAssertEqual(try Git.pendingOperation(at: f.path), "cherry-pick")
    expectFailure("already in progress") { try f.perform(.checkoutCommit(root)) }
    try f.perform(.abortOperation("cherry-pick"))
    XCTAssertEqual(try f.git(["rev-parse", "HEAD"]), main)
    expectFailure("in progress") { try f.perform(.cherryPick(commit: feature, mainline: nil)) }
    try f.write("shared.txt", "resolved\n"); _ = try f.git(["add", "shared.txt"])
    try f.perform(.continueOperation("cherry-pick"))
    XCTAssertEqual(try Git.pendingOperation(at: f.path), nil)
    XCTAssertEqual(try String(contentsOf: f.url.appendingPathComponent("shared.txt")), "resolved\n")
    expectFailure("no longer in progress") { try f.perform(.abortOperation("cherry-pick")) }
    print("PASS: conflict detection, mutation blocking, abort and staged-resolution continue")
}
