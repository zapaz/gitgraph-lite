import Foundation
import GitGraphCore

func checkSearchIndex() {
    let commits = [
        Commit(id: "ABC123", parents: [], author: "Élodie", decorations: "tag: v1.0", subject: "Fix: café ☕"),
        Commit(id: "def456", parents: [], author: "Runbot", decorations: "origin/main", subject: "docs: guide"),
        Commit(id: "ghi789", parents: [], author: "ZAPAZ", decorations: "feature/search", subject: "feat: marché")
    ]
    let index = HistorySearchIndex(commits)
    for query in ["", "  ", "fix", "CAFÉ", "élodie", "abc", "TAG: v1", "origin/main", "ZAPAZ", "☕", "marché", "missing"] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let expected = commits.indices.filter { i in
            let c = commits[i]
            return normalized.isEmpty || "\(c.subject) \(c.author) \(c.id) \(c.decorations)".lowercased().contains(normalized)
        }
        XCTAssertEqual(index.matching(query), expected)
    }
    print("PASS: indexed search preserves message/author/hash/ref matches, Unicode, case folding, whitespace and empty queries")
}

func checkHistorySnapshotReload() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("GitGraphFastHistory-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    func git(_ args: [String]) throws -> String { try Git.string(args, at: folder.path) }
    _ = try git(["init", "-b", "main"])
    for (key,value) in [("user.name","Performance Checks"),("user.email","performance@example.invalid"),("commit.gpgsign","false"),("core.hooksPath","/dev/null")] { _ = try git(["config",key,value]) }
    let unborn = try Git.load(at: folder.path, branch: nil, limit: 500)
    XCTAssertTrue(try Git.loadHistory(in: unborn, branchNames: nil, pins: [], limit: 500).commits.isEmpty)
    func commit(_ name: String) throws {
        try name.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        _ = try git(["add","."]); _ = try git(["commit","-m",name])
    }
    try commit("root"); let root = try git(["rev-parse","HEAD"])
    _ = try git(["switch","-c","feature"]); try commit("feature")
    _ = try git(["update-ref","refs/remotes/origin/feature","HEAD"])
    _ = try git(["config","remote.origin.url",folder.path])
    _ = try git(["switch","main"]); try commit("main")
    let snapshot = try Git.load(at: folder.path, branch: nil, limit: 500)
    let selections: [Set<String>?] = [nil, [], ["feature"], ["main","feature"], ["missing"]]
    for selection in selections {
        for limit in [1,500] {
            let fast = try Git.loadHistory(in: snapshot, branchNames: selection, pins: [], limit: limit)
            let fresh = try Git.load(at: folder.path, branchNames: selection, pins: [], limit: limit)
            XCTAssertEqual(fast.commits, fresh.commits)
            XCTAssertEqual(fast.signature, fresh.signature)
            XCTAssertEqual(fast.branchGroups, fresh.branchGroups)
        }
    }
    let linked = folder.appendingPathComponent("linked")
    _ = try git(["worktree","add","--detach",linked.path,"feature"])
    let addedTree = try Git.loadHistory(in: snapshot, branchNames: nil, pins: [], limit: 500)
    XCTAssertEqual(addedTree.worktrees.count, snapshot.worktrees.count+1)
    _ = try git(["worktree","remove",linked.path])
    let removedTree = try Git.loadHistory(in: addedTree, branchNames: nil, pins: [], limit: 500)
    XCTAssertEqual(removedTree.worktrees.count, snapshot.worktrees.count)
    _ = try git(["branch","external","feature"])
    let changed = try Git.loadHistory(in: snapshot, branchNames: ["external"], pins: [], limit: 500)
    XCTAssertTrue(changed.branchGroups.contains { $0.name == "external" })
    XCTAssertTrue(changed.commits.contains { $0.subject == "feature" })
    _ = try git(["branch","-D","external"])
    let deleted = try Git.loadHistory(in: changed, branchNames: ["external"], pins: [], limit: 500)
    XCTAssertTrue(!deleted.branchGroups.contains { $0.name == "external" })
    _ = try git(["tag","-a","fresh-tag","-m","Tag metadata changed"])
    let tagged = try Git.loadHistory(in: deleted, branchNames: nil, pins: [], limit: 500)
    XCTAssertTrue(tagged.references.contains { $0.name == "refs/tags/fresh-tag" })
    _ = try git(["switch","--detach",root])
    _ = try git(["branch","-D","main","feature"])
    _ = try git(["update-ref","-d","refs/remotes/origin/feature"])
    _ = try git(["tag","-d","fresh-tag"])
    let emptyFilter = try Git.load(at: folder.path, branches: [], limit: 500)
    XCTAssertTrue(emptyFilter.commits.isEmpty)
    let detached = try Git.loadHistory(in: emptyFilter, branchNames: nil, pins: [], limit: 500)
    XCTAssertEqual(detached.commits.map(\.id), [root])
    print("PASS: fast branch history matches fresh loads, limits/pins/remotes, refreshes external ref/tag/worktree changes, and handles unborn and refless detached HEAD")
}
