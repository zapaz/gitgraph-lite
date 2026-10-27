import Foundation
import GitGraphCore

func XCTAssertTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(value, "Expected true", file: file, line: line)
}
func XCTAssertEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    precondition(lhs == rhs, "Expected \(lhs) == \(rhs)", file: file, line: line)
}
func XCTAssertNotEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    precondition(lhs != rhs, "Expected different values", file: file, line: line)
}
func XCTUnwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw GitErrorForCheck.missingValue }; return value
}
enum GitErrorForCheck: Error { case missingValue }

final class GitGraphCoreTests {
    func testGraphMaintainsPathsThroughMergeAndBranchConvergence() {
        // M merges B and C, both of which descend from A.
        let rows = GraphLayout.make([
            Commit(id: "M", parents: ["B", "C"]),
            Commit(id: "B", parents: ["A"]),
            Commit(id: "C", parents: ["A"]),
            Commit(id: "A", parents: [])
        ])
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows[0].edges.filter { $0.segment == 2 }.count, 2)
        XCTAssertEqual(rows[1].edges.filter { $0.segment == 0 }.count, 1)
        XCTAssertEqual(rows[2].lane, 1)
        XCTAssertEqual(rows[2].edges.first { $0.segment == 2 }?.to, 0)
        XCTAssertEqual(rows[3].edges.filter { $0.segment == 2 }.count, 0)
        XCTAssertEqual(rows.map(\.width).max(), 2)
    }

    func testRealRepositoryRootMergeComparisonAndLiteralPaths() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("GitGraphLiteTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        let path = url.path
        func git(_ args: [String]) throws -> String {
            try Git.string(["-c", "user.name=Test User", "-c", "user.email=test@example.invalid"] + args, at: path)
        }
        func write(_ name: String, _ contents: String) throws { try contents.write(to: url.appendingPathComponent(name), atomically: true, encoding: .utf8) }
        _ = try git(["init", "-b", "main"])
        let empty = try Git.load(at: path, branch: nil, limit: 500)
        XCTAssertTrue(empty.commits.isEmpty)
        let filename = "[notes] é\tfile.txt"
        try write(filename, "first\n")
        _ = try git(["add", "--", filename]); _ = try git(["commit", "-m", "Root commit 🌱"])
        let root = try git(["rev-parse", "HEAD"])
        let rootFiles = try Git.files(at: path, target: root, base: nil)
        XCTAssertEqual(rootFiles.map(\.path), [filename])
        XCTAssertEqual(rootFiles.first?.status, "A")
        XCTAssertTrue(try Git.patch(at: path, target: root, base: nil, file: filename).contains("+first"))
        _ = try git(["checkout", "-b", "feature"])
        try write("feature.txt", "feature\n")
        _ = try git(["add", "."]); _ = try git(["commit", "-m", "Feature"])
        _ = try git(["checkout", "main"])
        try write(filename, "first\nsecond\n")
        _ = try git(["add", "."]); _ = try git(["commit", "-m", "Main change"])
        let beforeMerge = try Git.signature(at: path)
        _ = try git(["merge", "--no-ff", "feature", "-m", "Merge feature"])
        let repo = try Git.load(at: path, branch: nil, limit: 500)
        XCTAssertEqual(repo.commits.count, 4)
        XCTAssertEqual(repo.commits.first?.parents.count, 2)
        XCTAssertEqual(repo.commits.last?.subject, "Root commit 🌱")
        XCTAssertNotEqual(repo.signature, beforeMerge)
        let merge = try XCTUnwrap(repo.commits.first?.id)
        XCTAssertEqual(try Git.files(at: path, target: merge, base: nil).map(\.path), ["feature.txt"])
        XCTAssertEqual(Set(try Git.files(at: path, target: merge, base: root).map(\.path)), Set([filename, "feature.txt"]))
        XCTAssertTrue(try Git.patch(at: path, target: merge, base: root, file: filename).contains("+second"))
        let filtered = try Git.load(at: path, branch: "refs/heads/feature", limit: 500)
        XCTAssertEqual(filtered.commits.count, 2)
        XCTAssertEqual(filtered.branch, "main")
        XCTAssertEqual(try git(["branch", "--show-current"]), "main")
        XCTAssertEqual(GraphLayout.make(repo.commits).count, 4)
        _ = try git(["checkout", "--detach", root])
        XCTAssertEqual(try Git.load(at: path, branch: nil, limit: 500).branch, "Detached HEAD")
        XCTAssertEqual(try git(["status", "--porcelain"]), "")
    }
}

let checks = GitGraphCoreTests()
checks.testGraphMaintainsPathsThroughMergeAndBranchConvergence()
print("PASS: merge graph topology and lane convergence")
try checks.testRealRepositoryRootMergeComparisonAndLiteralPaths()
print("PASS: empty repository, root commit, merge diff, comparison, Unicode/literal paths, branch filter, detached HEAD, read-only checks")
checkVisualDiff()
checkUnifiedDiff()
try checkCommitActions()
try checkHistoryRewrites()
try checkConflicts()
try checkWorktrees()
checkReferenceLabels()
try checkDateOrderedHistory()
try checkAutomaticNavigation()
try checkDedicatedWorkspaceRebase()

try checkBranchBrowser()
checkHistoryGrouping()
checkFileTree()
checkInterleavedHistoryGroups()

checkSearchIndex()
try checkHistorySnapshotReload()
