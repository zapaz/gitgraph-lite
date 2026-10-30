// Test the real item menus and hit targets; Git mutations are covered with disposable remotes.
func checkAdaptiveCommitMenu() throws {
    let suite = "GitGraphLite.ItemMenuChecks." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let usage = ActionUsage(defaults: defaults)
    var invocations = 0
    func build(_ kind: ActionItemKind) -> NSMenu {
        let menu = ItemMenuBuilder(kind: kind, usage: usage)
        for id in [CommitActionID.copyHash,.copyShortHash,.merge] { menu.add(id.title,id:id) { invocations += 1 } }
        return menu.finish()
    }
    func ids(_ menu: NSMenu) -> [String] { menu.items.compactMap { $0.identifier?.rawValue } }
    func click(_ id: CommitActionID, in menu: NSMenu) {
        let item = menu.items.first { $0.identifier?.rawValue == id.rawValue }!
        precondition(item.submenu == nil && item.action != nil)
        precondition(NSApp.sendAction(item.action!,to:item.target,from:item))
    }
    precondition(ids(build(.commit)) == ["copyHash","copyShortHash","merge"])
    click(.merge,in:build(.branch))
    precondition(usage.count(.merge,kind:.branch) == 1 && usage.count(.merge,kind:.commit) == 0)
    precondition(ids(build(.branch)).first == "merge" && ids(build(.commit)).first == "copyHash")
    let restored = ActionUsage(defaults:UserDefaults(suiteName:suite)!)
    precondition(restored.count(.merge,kind:.branch) == 1)
    let disabled = ItemMenuBuilder(kind:.tag,usage:usage)
    let blocked = disabled.add("Disabled",id:.deleteTag,enabled:false) { invocations += 1 }
    (blocked.representedObject as! MenuCommand).invoke(blocked)
    precondition(usage.count(.deleteTag,kind:.tag) == 0 && invocations == 1)
    defaults.set(["copyHash":4],forKey:"commitActionClickCounts.v1")
    precondition(restored.count(.copyHash) == 4)
    let freshSuite = suite+".fresh", fresh = UserDefaults(suiteName:suite+".fresh")!
    defer { fresh.removePersistentDomain(forName:freshSuite) }
    precondition(ActionUsage(defaults:fresh).count(.copyHash) == 0)

    let base = FileManager.default.temporaryDirectory.appendingPathComponent("GitGraphMenuUI-"+UUID().uuidString+" é folder")
    let path = base.appendingPathComponent("repo").path
    try FileManager.default.createDirectory(atPath:path,withIntermediateDirectories:true)
    defer { try? FileManager.default.removeItem(at:base) }
    func git(_ args:[String]) throws -> String { try Git.string(args,at:path) }
    _ = try git(["init","-b","main"])
    for (k,v) in [("user.name","Menu Checks"),("user.email","menu@example.invalid"),("commit.gpgsign","false"),("core.hooksPath","/dev/null")] { _ = try git(["config",k,v]) }
    _ = try git(["commit","--allow-empty","-m","Root"])
    let hash = try git(["rev-parse","HEAD"])
    _ = try git(["branch","feature"]); _ = try git(["tag","release-tag"])
    _ = try git(["remote","add","origin",base.appendingPathComponent("unused.git").path])
    _ = try git(["update-ref","refs/remotes/origin/feature",hash])
    _ = try Git.openLocalBranch("feature",at:path)
    let repo = try Git.load(at:path,branch:nil,limit:500)
    let tree = repo.worktrees.first { $0.branch == "refs/heads/feature" }!
    let controller = Controller(); controller.timer?.invalidate(); controller.actionUsage = usage
    controller.repository = repo; controller.commits = repo.commits; controller.graph = GraphLayout.make(repo.commits)
    controller.labelsByCommit = Dictionary(grouping:repo.references,by:\.target).mapValues { ReferenceLabel.make($0,currentBranch:repo.branch) }
    controller.activeHead = hash; controller.applySearch(selected:[])
    defer { controller.window?.close() }
    func has(_ menu:NSMenu,_ expected:[String]) {
        precondition(Set(ids(menu)) == Set(expected),"Unexpected items: \(ids(menu))")
        precondition(menu.items.allSatisfy { $0.submenu == nil && !$0.isSeparatorItem },"Short item menus never contain Plus or unrelated ref submenus")
    }
    let commitIDs = ["addTag","createBranch","cherryPick","copyHash","copyShortHash"]
    let branchIDs = ["checkout","pushBranch","pullBranch","renameBranch","merge","copyBranchName"]
    let tagIDs = ["deleteTag","pushTag","copyTagName"]
    let treeIDs = ["openWorktree","revealWorktree","copyWorktreePath","deleteWorktree"]
    has(controller.commitMenu(at:0)!,commitIDs)
    has(controller.branchMenu(reference:"refs/heads/feature",repo:repo)!,branchIDs)
    has(controller.tagMenu(reference:"refs/tags/release-tag",repo:repo)!,tagIDs)
    has(controller.worktreeMenu(tree,repo:repo),treeIDs)
    let remote = controller.branchMenu(reference:"refs/remotes/origin/feature",repo:repo)!
    precondition(remote.items.first { $0.identifier?.rawValue == "pushBranch" }?.isEnabled == false)
    precondition(remote.items.first { $0.identifier?.rawValue == "renameBranch" }?.isEnabled == false)
    let main = repo.worktrees.first { $0.isMain }!
    precondition(controller.worktreeMenu(main,repo:repo).items.first { $0.identifier?.rawValue == "deleteWorktree" }?.isEnabled == false)
    let pasteboard = NSPasteboard.general
    let previous = pasteboard.pasteboardItems?.map { item in item.types.compactMap { type in item.data(forType:type).map { (type,$0) } } } ?? []
    defer {
        pasteboard.clearContents()
        let items = previous.map { values in let item = NSPasteboardItem(); for (type,data) in values { item.setData(data,forType:type) }; return item }
        pasteboard.writeObjects(items)
    }
    click(.copyHash,in:controller.commitMenu(at:0)!); precondition(pasteboard.string(forType:.string) == hash)
    click(.copyShortHash,in:controller.commitMenu(at:0)!); precondition(pasteboard.string(forType:.string) == String(hash.prefix(10)))
    click(.copyWorktreePath,in:controller.worktreeMenu(tree,repo:repo)); precondition(pasteboard.string(forType:.string) == tree.path)
    // Exercise actual badge geometry, including the remote compartment of a combined label.
    controller.table.layoutSubtreeIfNeeded()
    let subjectIndex = controller.table.tableColumns.firstIndex { $0.identifier.rawValue == "subject" }!
    let cell = controller.table.view(atColumn:subjectIndex,row:0,makeIfNecessary:true) as! CommitCell
    let image = NSImage(size:cell.bounds.size); image.lockFocus(); cell.draw(cell.bounds); image.unlockFocus()
    let expectedTargets:[HistoryMenuTarget] = [.commit,.reference("refs/heads/feature"),.reference("refs/remotes/origin/feature"),.reference("refs/tags/release-tag"),.worktree(tree.path)]
    for target in expectedTargets {
        let found = (0..<Int(cell.bounds.width)).first { cell.contextTarget(at:NSPoint(x:CGFloat($0),y:cell.bounds.midY)) == target }
        precondition(found != nil,"A visible badge must have an explicit target: \(target)")
        let point = cell.convert(NSPoint(x:CGFloat(found!),y:cell.bounds.midY),to:nil)
        let event = NSEvent.mouseEvent(with:.rightMouseDown,location:point,modifierFlags:[],timestamp:0,windowNumber:controller.window!.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
        let menu = controller.table.menu(for:event)!
        switch target {
        case .commit: has(menu,commitIDs)
        case .worktree: has(menu,treeIDs)
        case .reference(let name): has(menu,name.hasPrefix("refs/tags/") ? tagIDs : branchIDs)
        }
    }
    precondition(cell.contextTarget(at:NSPoint(x:cell.bounds.maxX+1,y:cell.bounds.midY)) == .commit)
    let manager = WorktreeManager(owner:controller,path:path); manager.trees = repo.worktrees; manager.table.reloadData()
    let row = manager.trees.firstIndex { $0.path == tree.path }!
    has(manager.table.menuProvider!(row,"path")!,treeIDs)
    has(manager.table.menuProvider!(row,"branch")!,branchIDs)
    manager.close()
    let picker = BranchPicker(); picker.owner = controller; _ = picker.view
    func buttons(_ view: NSView) -> [CallbackButton] {
        (view as? CallbackButton).map { [$0] } ?? view.subviews.flatMap { buttons($0) }
    }
    let branchButton = buttons(picker.view).first { $0.title == "feature" }!
    let rightClick = NSEvent.mouseEvent(with:.rightMouseDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:controller.window!.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
    has(branchButton.menu(for:rightClick)!,branchIDs)
    let recovery = NSMenuItem(title:"Continue",action:#selector(Controller.continueCurrentOperation),keyEquivalent:"")
    precondition(!controller.validateMenuItem(recovery))
    _ = try git(["update-ref", "refs/remotes/origin/main", hash])
    _ = try git(["switch", "-c", "prod"])
    try "keep prod edits".write(to: URL(fileURLWithPath: path).appendingPathComponent("dirty.txt"), atomically: true, encoding: .utf8)
    let switched = try Git.load(at: path, branch: nil, limit: 500)
    controller.repository = switched
    let pull = controller.branchMenu(reference: "refs/remotes/origin/main", repo: switched)!.items.first { $0.identifier?.rawValue == "pullBranch" }!
    precondition(pull.isEnabled, "Remote main must allow Pull without editing the folder externally switched to prod")
    precondition(controller.branchMenu(reference: "refs/heads/main", repo: switched)!.items.first { $0.identifier?.rawValue == "pullBranch" }!.isEnabled)
    controller.loading = true
    precondition(!controller.branchMenu(reference: "refs/remotes/origin/main", repo: switched)!.items.first { $0.identifier?.rawValue == "pullBranch" }!.isEnabled)
    controller.loading = false
    print("PASS: Pull enabled on local/remote main despite the prod association mismatch; loading still blocks actions")
    print("PASS: four short typed menus, per-item frequency persistence, legacy counts, disabled guards, full/10-character hashes and exact workspace path; real badge/table right-click routing targets commit/local/remote/tag/worktree correctly")
}
try checkAdaptiveCommitMenu()
