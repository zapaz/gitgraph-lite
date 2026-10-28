import Foundation
import GitGraphCore

func checkRepositoryItemActions() throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("GitGraphItemActions-" + UUID().uuidString)
    let repo = base.appendingPathComponent("repo"), origin = base.appendingPathComponent("origin.git"), producer = base.appendingPathComponent("producer")
    try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }
    func git(_ args: [String], at location: URL? = nil) throws -> String { try Git.string(args, at: (location ?? repo).path) }
    func configure(_ location: URL) throws {
        for (key,value) in [("user.name","Item Checks"),("user.email","items@example.invalid"),("commit.gpgsign","false"),("tag.gpgsign","false"),("core.hooksPath","/dev/null")] { _ = try git(["config",key,value],at:location) }
    }
    func commit(_ name: String, at location: URL) throws -> String {
        try name.write(to: location.appendingPathComponent(name+".txt"), atomically: true, encoding: .utf8)
        _ = try git(["add","."],at:location); _ = try git(["commit","-m",name],at:location)
        return try git(["rev-parse","HEAD"],at:location)
    }
    func fails(_ text: String, _ body: () throws -> Void) {
        do { try body(); preconditionFailure("Expected " + text) }
        catch { precondition(error.localizedDescription.localizedCaseInsensitiveContains(text), "Unexpected error: \(error)") }
    }
    _ = try git(["init","-b","main"]); try configure(repo)
    let root = try commit("root",at:repo)
    _ = try git(["init","--bare",origin.path]); _ = try git(["remote","add","origin",origin.path])
    _ = try git(["branch","feature"])
    _ = try git(["tag","-a","release-one","-m","Annotated selected tag"])
    _ = try git(["tag","-a","do-not-publish","-m","Unselected tag"])
    _ = try git(["config","push.followTags","true"]); _ = try git(["config","remote.origin.mirror","true"])
    try "keep local edits".write(to: repo.appendingPathComponent("untracked.txt"),atomically:true,encoding:.utf8)
    _ = try Git.performItem(.pushBranch("feature"),at:repo.path,expectedSignature:Git.signature(at:repo.path))
    XCTAssertEqual(try git(["rev-parse","refs/heads/feature"],at:origin),root)
    fails("revision") { _ = try git(["rev-parse","--verify","refs/heads/main"],at:origin) }
    XCTAssertEqual(try git(["tag","--list"],at:origin),"")
    _ = try Git.performItem(.pushTag("release-one"),at:repo.path)
    XCTAssertEqual(try git(["rev-parse","refs/tags/release-one"],at:origin),try git(["rev-parse","refs/tags/release-one"]))
    XCTAssertEqual(try git(["tag","--list"],at:origin),"release-one")
    let stale = try Git.signature(at:repo.path); _ = try git(["tag","changed"])
    fails("repository changed") { _ = try Git.performItem(.pushTag("changed"),at:repo.path,expectedSignature:stale) }
    _ = try git(["clone",origin.path,producer.path]); try configure(producer)
    _ = try git(["switch","feature"],at:producer)
    let remote1 = try commit("remote-one",at:producer); _ = try git(["push","origin","feature"],at:producer)
    _ = try Git.performItem(.pullBranch("feature"),at:repo.path)
    let trees = try Git.worktrees(at:repo.path)
    let workspace = trees.first { $0.branch == "refs/heads/feature" }!
    XCTAssertEqual(try git(["rev-parse","HEAD"],at:URL(fileURLWithPath:workspace.path)),remote1)
    XCTAssertEqual(try git(["symbolic-ref","--short","HEAD"]),"main")
    XCTAssertEqual(try git(["rev-parse","HEAD"]),root)
    XCTAssertEqual(try String(contentsOf:repo.appendingPathComponent("untracked.txt")),"keep local edits")
    let workspaceURL = URL(fileURLWithPath:workspace.path)
    let localTip = try commit("local-only",at:workspaceURL)
    _ = try commit("remote-two",at:producer); _ = try git(["push","origin","feature"],at:producer)
    fails("fast-forward") { _ = try Git.performItem(.pullBranch("feature"),at:repo.path) }
    XCTAssertEqual(try git(["rev-parse","HEAD"],at:workspaceURL),localTip)
    let publishedTip = try git(["rev-parse","refs/heads/feature"],at:origin)
    fails("rejected") { _ = try Git.performItem(.pushBranch("feature"),at:repo.path) }
    XCTAssertEqual(try git(["rev-parse","refs/heads/feature"],at:origin),publishedTip)
    try "preserve".write(to:workspaceURL.appendingPathComponent("dirty.txt"),atomically:true,encoding:.utf8)
    fails("local changes") { _ = try Git.performItem(.pullBranch("feature"),at:repo.path) }
    _ = try Git.performItem(.renameBranch(old:"feature",new:"renamed"),at:repo.path)
    let renamed = try Git.worktrees(at:repo.path).first { $0.path == workspace.path }!
    XCTAssertEqual(renamed.branch,"refs/heads/renamed"); XCTAssertEqual(renamed.assignedBranch,"refs/heads/renamed")
    XCTAssertTrue(renamed.associationIssue == nil)
    XCTAssertEqual(try String(contentsOf:workspaceURL.appendingPathComponent("dirty.txt")),"preserve")
    XCTAssertEqual(try git(["rev-parse","HEAD"],at:workspaceURL),localTip)
    _ = try Git.performItem(.renameBranch(old:"main",new:"trunk"),at:repo.path)
    XCTAssertEqual(try git(["symbolic-ref","--short","HEAD"]),"trunk")
    XCTAssertTrue(try Git.worktrees(at:repo.path).first { $0.isMain }?.associationIssue == nil)
    // A fresh remote-only name materializes one local branch/workspace on Pull.
    _ = try git(["branch","remote-only"],at:producer); _ = try git(["push","origin","remote-only"],at:producer)
    _ = try Git.performItem(.pullBranch("remote-only"),at:repo.path)
    XCTAssertEqual(try Git.worktrees(at:repo.path).filter { $0.branch == "refs/heads/remote-only" }.count,1)
    XCTAssertEqual(try git(["symbolic-ref","--short","HEAD"]),"trunk")
    // No origin: fail without modifying refs or creating a workspace.
    _ = try git(["remote","remove","origin"])
    fails("origin") { _ = try Git.performItem(.pushBranch("trunk"),at:repo.path) }
    print("PASS: item pushes target one branch/tag only, preserve annotated tags, reject stale state; pulls fast-forward the selected workspace only, reject divergence/dirty files; rename preserves workspace binding and edits")
}
