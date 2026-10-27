import Foundation
import GitGraphCore

func checkBranchBrowser() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("GitGraphBrowser-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    func git(_ args: [String]) throws -> String { try Git.string(["-c", "user.name=Browser", "-c", "user.email=browser@example.invalid", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null"] + args, at: folder.path) }
    _ = try git(["init", "-b", "main"])
    _ = try git(["commit", "--allow-empty", "-m", "root"])
    let root = try git(["rev-parse", "HEAD"])
    _ = try git(["remote", "add", "origin", "/nonexistent-test-origin"])
    _ = try git(["switch", "-c", "feature/ui"])
    _ = try git(["commit", "--allow-empty", "-m", "local feature"])
    let local = try git(["rev-parse", "HEAD"])
    _ = try git(["switch", "--detach", root])
    _ = try git(["commit", "--allow-empty", "-m", "remote divergence"])
    let remote = try git(["rev-parse", "HEAD"])
    _ = try git(["update-ref", "refs/remotes/origin/feature/ui", remote])
    _ = try git(["update-ref", "refs/remotes/origin/remote-only", remote])
    _ = try git(["symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/feature/ui"])
    _ = try git(["switch", "main"])
    _ = try git(["commit", "--allow-empty", "-m", "main advance"])
    let main = try git(["rev-parse", "HEAD"])
    _ = try git(["branch", "other", root]); _ = try git(["branch", "master", root])
    let before = try git(["rev-parse", "HEAD"])
    let repo = try Git.load(at: folder.path, branches: nil, limit: 500)
    let group = try XCTUnwrap(repo.branchGroups.first { $0.name == "feature/ui" })
    XCTAssertEqual(group.references, ["refs/heads/feature/ui", "refs/remotes/origin/feature/ui"])
    XCTAssertTrue(!repo.branchGroups.contains { $0.name == "HEAD" })
    let filters = BranchGroup.historyReferences(repo.branchGroups, selection: ["feature/ui", "other"], pins: [])
    let history = try Git.load(at: folder.path, branches: filters, limit: 500)
    XCTAssertEqual(Set(history.commits.map(\.id)), Set([root, local, remote, main]))
    let onlyPins = BranchGroup.historyReferences(repo.branchGroups, selection: [], pins: ["remote-only"])
    XCTAssertTrue(onlyPins!.contains("refs/heads/main")); XCTAssertTrue(onlyPins!.contains("refs/heads/master")); XCTAssertTrue(onlyPins!.contains("refs/remotes/origin/remote-only"))
    XCTAssertTrue(BranchGroup.historyReferences(repo.branchGroups, selection: nil, pins: []) == nil)
    XCTAssertTrue(try Git.load(at: folder.path, branches: [], limit: 500).commits.isEmpty)
    let created = try Git.automaticWorktree(at: folder.path, branch: "remote-only")
    XCTAssertEqual(created.branch, "remote-only"); XCTAssertTrue(created.didCreateBranch)
    XCTAssertEqual(try Git.string(["rev-parse", "--symbolic-full-name", "@{upstream}"], at: created.path), "refs/remotes/origin/remote-only")
    XCTAssertEqual(try git(["rev-parse", "HEAD"]), before)
    XCTAssertEqual(try Git.automaticWorktree(at: folder.path, branch: "remote-only").path, created.path)
    print("PASS: branch grouping, divergent local/origin history union, multiple selection, mandatory and custom pins, symbolic HEAD exclusion, automatic remote-only worktrees and tracking")
}

func checkHistoryGrouping() {
    let commits = (0..<48).map { Commit(id: "c\($0)", parents: $0 == 47 ? [] : ["c\($0+1)"]) }
    let graph = GraphLayout.make(commits)
    let groups = HistoryGroup.make(commits, graph: graph, protected: ["c0", "c24", "c47"])
    XCTAssertTrue(!groups.isEmpty)
    let hidden = Set(groups.flatMap { Array($0.indices) })
    XCTAssertTrue(!hidden.contains(0) && !hidden.contains(24) && !hidden.contains(47))
    XCTAssertTrue(groups.allSatisfy { $0.indices.count >= 5 && $0.indices.count <= 20 })
    let branching = [Commit(id: "merge", parents: ["c0", "side"])] + commits + [Commit(id: "side", parents: ["c30"])]
    let junctionGroups = HistoryGroup.make(branching, graph: GraphLayout.make(branching), protected: [])
    for group in junctionGroups {
        let ids = branching[group.indices].map(\.id)
        XCTAssertTrue(!ids.contains("merge") && !ids.contains("c30"))
    }
    XCTAssertTrue(HistoryGroup.make(Array(commits.prefix(4)), graph: GraphLayout.make(Array(commits.prefix(4))), protected: []).isEmpty)
    print("PASS: bounded linear history groups preserve refs, merge commits, fork points, root and short histories")
}

func checkFileTree() {
    let files = [ChangedFile(status: "M", path: "Sources/Core/Git.swift"), ChangedFile(status: "A", path: "README.md"), ChangedFile(status: "D", path: "Sources/UI/Tree.swift"), ChangedFile(status: "M", path: "Sources/Core/é\tname.swift")]
    let tree = FileTreeRow.make(files, tree: true)
    XCTAssertEqual(tree.map(\.path), ["Sources", "Sources/Core", "Sources/Core/é\tname.swift", "Sources/Core/Git.swift", "Sources/UI", "Sources/UI/Tree.swift", "README.md"])
    XCTAssertEqual(tree.first?.depth, 0)
    XCTAssertEqual(tree.first { $0.path == "Sources/Core/Git.swift" }?.fileIndex, 0)
    let collapsed = FileTreeRow.make(files, tree: true, collapsed: ["Sources/Core"])
    XCTAssertTrue(!collapsed.contains { $0.path == "Sources/Core/Git.swift" }); XCTAssertTrue(collapsed.contains { $0.path == "Sources/UI/Tree.swift" })
    XCTAssertEqual(FileTreeRow.make(files, tree: false).map(\.fileIndex), [0, 1, 2, 3])
    XCTAssertTrue(FileTreeRow.make([], tree: true).isEmpty)
    print("PASS: file tree ordering, nesting, folder collapse, Unicode paths and original diff indices in both modes")
}
