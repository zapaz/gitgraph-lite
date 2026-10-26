import Foundation
import GitGraphCore

func checkReferenceLabels() {
    let refs = [
        GitReference(name: "refs/heads/main", target: "a"),
        GitReference(name: "refs/remotes/origin/main", target: "a"),
        GitReference(name: "refs/remotes/upstream/main", target: "a"),
        GitReference(name: "refs/remotes/origin/HEAD", target: "a", symbolic: true),
        GitReference(name: "refs/remotes/origin/feature/long-branch-name", target: "a"),
        GitReference(name: "refs/tags/pr,111", target: "a"),
        GitReference(name: "refs/tags/v1.0", target: "a")
    ]
    let labels = ReferenceLabel.make(refs, currentBranch: "main")
    XCTAssertEqual(labels.count, 4)
    XCTAssertEqual(labels[0].name, "main"); XCTAssertTrue(labels[0].isCurrent)
    XCTAssertEqual(labels[0].remotes, ["origin", "upstream"])
    XCTAssertEqual(labels[0].fullNames.count, 3)
    XCTAssertEqual(labels[1].kind, .remote)
    XCTAssertEqual(labels[1].name, "origin/feature/long-branch-name")
    XCTAssertEqual(labels[2].kind, .tag); XCTAssertEqual(labels[2].name, "pr,111")
    let diverged = ReferenceLabel.make([GitReference(name: "refs/heads/main", target: "a"), GitReference(name: "refs/remotes/origin/main", target: "b")], currentBranch: "main")
    XCTAssertEqual(diverged.count, 2); XCTAssertTrue(diverged[0].remotes.isEmpty)
    print("PASS: separate branch/tag labels, local/remote grouping, divergent refs, symbolic HEAD filtering and comma-containing tag names")
}

func checkDateOrderedHistory() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("GitGraphHistory-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    func git(_ args: [String]) throws -> String { try Git.string(args, at: folder.path) }
    _ = try git(["init", "-b", "main"])
    for (name, value) in [("user.name", "History Checks"), ("user.email", "history@example.invalid"), ("commit.gpgsign", "false"), ("core.hooksPath", "/dev/null")] { _ = try git(["config", name, value]) }
    func commit(_ name: String, tick: Int) throws {
        try name.write(to: folder.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
        _ = try git(["add", "."])
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", folder.path, "commit", "-m", name]
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_AUTHOR_DATE"] = "\(1700000000 + tick*60) +0000"
        environment["GIT_COMMITTER_DATE"] = "\(1700000000 + tick*60) +0000"
        process.environment = environment; process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit(); precondition(process.terminationStatus == 0)
    }
    try commit("root", tick: 1)
    _ = try git(["switch", "-c", "feature"])
    try commit("feature-old", tick: 2); try commit("feature-new", tick: 4)
    _ = try git(["switch", "main"])
    try commit("main-old", tick: 3); try commit("main-new", tick: 5)
    let history = try Git.load(at: folder.path, branch: nil, limit: 500)
    XCTAssertEqual(history.commits.map(\.subject), ["main-new", "feature-new", "main-old", "feature-old", "root"])
    let positions = Dictionary(uniqueKeysWithValues: history.commits.enumerated().map { ($0.element.id, $0.offset) })
    for (i, commit) in history.commits.enumerated() {
        for parent in commit.parents { XCTAssertTrue(positions[parent].map { $0 > i } ?? true) }
    }
    XCTAssertEqual(history.branch, "main")
    XCTAssertEqual(GraphLayout.make(history.commits).count, 5)
    print("PASS: chronological interleaving of branches, child-before-parent topology, and unchanged active branch")
}
