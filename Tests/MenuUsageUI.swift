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
        precondition(menu.items.allSatisfy { $0.submenu == nil || $0.title == "Delete" },"Only the branch Delete submenu nests: \(menu.items.map(\.title))")
        if expected == branchIDs { precondition(ids(menu.items.first { $0.title == "Delete" }!.submenu!) == deleteIDs) }
        if expected == tagIDs { precondition(!menu.items.contains { $0.isSeparatorItem },"Usage-ranked menus have no separators") }
    }
    let commitIDs = ["addTag","createBranch","cherryPick","copyHash","copyShortHash","copySubject"]
    let branchIDs = ["openBranch","merge","pushBranch","pullBranch","renameBranch","copyBranchName","copyWorktreePath"]
    let deleteIDs = ["deleteBranchEverywhere","deleteBranch","deleteRemoteBranch","deleteWorktree"]
    let tagIDs = ["deleteTag","pushTag","copyTagName"]
    let treeIDs = ["openWorktree","deleteWorktree","copyWorktreePath"]
    has(controller.commitMenu(at:0)!,commitIDs)
    let commitMenu = controller.commitMenu(at:0)!
    precondition(commitMenu.items.map { $0.isSeparatorItem ? "-" : $0.title } == ["Add Tag…","Create Branch…","-","Cherry Pick…","-","Copy Hash","Copy Short Hash","Copy Subject"],"Commit menu keeps its fixed order: \(commitMenu.items.map(\.title))")
    has(controller.branchMenu(reference:"refs/heads/feature",repo:repo)!,branchIDs)
    has(controller.tagMenu(reference:"refs/tags/release-tag",repo:repo)!,tagIDs)
    has(controller.worktreeMenu(tree,repo:repo),treeIDs)
    func enabled(_ menu: NSMenu,_ id: String) -> Bool { menu.items.first { $0.identifier?.rawValue == id }!.isEnabled }
    let name = controller.branchMenu(reference:"refs/heads/feature",repo:repo)!
    precondition(controller.worktreeMenu(tree,repo:repo).items.map { $0.isSeparatorItem ? "-" : $0.title } == ["Open Worktree","-","Delete Worktree","-","Copy Worktree Path"])
    precondition(name.items.map { $0.isSeparatorItem ? "-" : $0.title } == ["Open Branch","Merge into Current","-","Push","Pull","-","Rename…","Delete","-","Copy Branch Name","Copy Worktree Path"],"\(name.items.map(\.title))")
    let delete = name.items.first { $0.title == "Delete" }!.submenu!
    precondition(delete.items.map(\.title) == ["Local + Origin","Local Branch","On origin","Worktree"])
    precondition(enabled(name,"openBranch") && enabled(name,"copyWorktreePath"))
    precondition(!enabled(name,"pushBranch"),"Push is greyed while origin is at the same commit")
    precondition(!enabled(name,"pullBranch"),"Pull is greyed while the local branch is at the same commit")
    precondition(!enabled(delete,"deleteBranch") && !enabled(delete,"deleteBranchEverywhere"),"A branch with a worktree cannot be deleted")
    precondition(enabled(delete,"deleteRemoteBranch") && enabled(delete,"deleteWorktree"))
    for other in ["refs/remotes/origin/feature"] { precondition(controller.branchMenu(reference:other,repo:repo)!.items.map(\.title) == name.items.map(\.title),"Same menu from every badge zone") }
    let main = repo.worktrees.first { $0.isMain }!
    precondition(controller.worktreeMenu(main,repo:repo).items.first { $0.identifier?.rawValue == "deleteWorktree" }?.isEnabled == false)
    // The worktree shown in the window can be deleted too: Git runs from the main worktree, then the window moves there.
    let shown = try Git.load(at:tree.path,branch:nil,limit:500)
    let shownDelete = controller.branchMenu(reference:"refs/heads/feature",repo:shown)!.items.first { $0.title == "Delete" }!.submenu!
    precondition(enabled(shownDelete,"deleteWorktree"),"The displayed worktree can be deleted")
    let pasteboard = NSPasteboard.general
    let previous = pasteboard.pasteboardItems?.map { item in item.types.compactMap { type in item.data(forType:type).map { (type,$0) } } } ?? []
    defer {
        pasteboard.clearContents()
        let items = previous.map { values in let item = NSPasteboardItem(); for (type,data) in values { item.setData(data,forType:type) }; return item }
        pasteboard.writeObjects(items)
    }
    click(.copyHash,in:controller.commitMenu(at:0)!); precondition(pasteboard.string(forType:.string) == hash)
    click(.copyShortHash,in:controller.commitMenu(at:0)!); precondition(pasteboard.string(forType:.string) == String(hash.prefix(10)))
    click(.copySubject,in:controller.commitMenu(at:0)!); precondition(pasteboard.string(forType:.string) == "Root")
    // Each action opens one popup; a success reports what was done and every shown value can be copied.
    let popup = ActionPopup(title:"Probe",facts:[.init(label:"Commit",value:hash)],parent:nil)
    var copied: [String] = []; popup.copy = { copied.append($0) }
    popup.showRunning("Working"); precondition(popup.phase == .running)
    popup.showFailure("Boom"); precondition(popup.phase == .failure)
    func copyButtons(_ view: NSView) -> [CallbackButton] { (view as? CallbackButton).map { $0.toolTip?.hasPrefix("Copy") == true ? [$0] : [] } ?? view.subviews.flatMap { copyButtons($0) } }
    copyButtons(popup.panel.contentView!).forEach { $0.performClick(nil) }
    precondition(copied == [hash,"Boom"],"Every value and the error text are copyable: \(copied)")
    func allButtons(_ view: NSView) -> [CallbackButton] { ((view as? CallbackButton).map { [$0] } ?? []) + view.subviews.flatMap { allButtons($0) } }
    let cross = allButtons(popup.panel.contentView!).first { $0.toolTip == "Close" && !$0.isHidden }
    precondition(cross != nil && popup.panel.isVisible,"An error popup has a visible close cross")
    cross!.performClick(nil); precondition(!popup.panel.isVisible,"The cross closes the popup")
    popup.showSuccess("Done"); precondition(popup.phase == .success && ActionPopup.successDelay == 3)
    popup.close()
    // A required field keeps the confirm button greyed out while empty.
    let field = NSTextField(string: "")
    let form = ActionPopup(title:"Add Tag",controls:[field],required:[field],parent:nil)
    var confirmed = 0
    form.askInput(confirm:"Add Tag") { confirmed += 1 }
    precondition(!form.canConfirm); field.stringValue = "v1"; precondition(form.canConfirm)
    form.close()
    // A stopped operation offers Abort and Continue instead of Back.
    let conflict = ActionPopup(title:"Cherry Pick",parent:nil)
    var recovered: [String] = []
    conflict.showFailure("conflict",back:{},actions:[("Abort",{ recovered.append("abort") }),("Continue",{ recovered.append("continue") })])
    let titles = allButtons(conflict.panel.contentView!).map(\.title).filter { !$0.isEmpty }
    precondition(titles == ["Abort","Continue"],"Conflict buttons: \(titles)")
    allButtons(conflict.panel.contentView!).filter { !$0.title.isEmpty }.forEach { $0.performClick(nil) }
    precondition(recovered == ["abort","continue"] && confirmed == 0)
    conflict.close()
    click(.copyWorktreePath,in:controller.worktreeMenu(tree,repo:repo)); precondition(pasteboard.string(forType:.string) == tree.path)
    // Exercise actual badge geometry, including the remote compartment of a combined label.
    controller.table.layoutSubtreeIfNeeded()
    let subjectIndex = controller.table.tableColumns.firstIndex { $0.identifier.rawValue == "subject" }!
    let cell = controller.table.view(atColumn:subjectIndex,row:0,makeIfNecessary:true) as! CommitCell
    let image = NSImage(size:cell.bounds.size); image.lockFocus(); cell.draw(cell.bounds); image.unlockFocus()
    let expectedTargets:[HistoryMenuTarget] = [.commit,.reference("refs/heads/feature"),.localBranch("refs/heads/feature"),.remoteBranch("refs/remotes/origin/feature"),.reference("refs/tags/release-tag")]
    for target in expectedTargets {
        let found = (0..<Int(cell.bounds.width)).first { cell.contextTarget(at:NSPoint(x:CGFloat($0),y:cell.bounds.midY)) == target }
        precondition(found != nil,"A visible badge must have an explicit target: \(target)")
        let point = cell.convert(NSPoint(x:CGFloat(found!),y:cell.bounds.midY),to:nil)
        let event = NSEvent.mouseEvent(with:.rightMouseDown,location:point,modifierFlags:[],timestamp:0,windowNumber:controller.window!.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
        let menu = controller.table.menu(for:event)!
        switch target {
        case .commit: has(menu,commitIDs)
        case .reference(let name): has(menu,name.hasPrefix("refs/tags/") ? tagIDs : branchIDs)
        case .localBranch, .remoteBranch, .worktree: has(menu,branchIDs)
        }
    }
    precondition(!(0..<Int(cell.bounds.width)).contains { cell.contextTarget(at:NSPoint(x:CGFloat($0),y:cell.bounds.midY)) == .worktree(tree.path) },"A branch's worktree has no icon of its own")
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
    // origin/main is one commit ahead, so Pull has something to bring.
    let ahead = try git(["commit-tree", hash + "^{tree}", "-p", hash, "-m", "Ahead on origin"])
    _ = try git(["update-ref", "refs/remotes/origin/main", ahead])
    _ = try git(["switch", "-c", "prod"])
    try "keep prod edits".write(to: URL(fileURLWithPath: path).appendingPathComponent("dirty.txt"), atomically: true, encoding: .utf8)
    let switched = try Git.load(at: path, branch: nil, limit: 500)
    controller.repository = switched
    let pull = controller.branchMenu(reference: "refs/remotes/origin/main", repo: switched)!.items.first { $0.identifier?.rawValue == "pullBranch" }!
    precondition(pull.isEnabled, "Remote main must allow Pull without editing the folder externally switched to prod")
    controller.loading = true
    precondition(!controller.branchMenu(reference: "refs/remotes/origin/main", repo: switched)!.items.first { $0.identifier?.rawValue == "pullBranch" }!.isEnabled)
    controller.loading = false
    // The window keeps any width the user gives it (a separator in the graph pane once pinned it).
    let window = controller.window!; let oldFrame = window.frame
    window.setFrame(NSRect(x: oldFrame.minX, y: oldFrame.minY, width: 1600, height: 900), display: false)
    window.contentView!.layoutSubtreeIfNeeded()
    precondition(window.frame.width == 1600, "Window width was forced to \(window.frame.width)")
    window.setFrame(oldFrame, display: false)
    // The Diff checkbox hides and restores the commit details pane, and remembers the choice.
    let previousDiff = UserDefaults.standard.object(forKey: "showDiff")
    controller.diffToggle.state = .off; controller.diffToggleChanged(controller.diffToggle)
    precondition(controller.detailsPane!.isHidden && UserDefaults.standard.bool(forKey: "showDiff") == false)
    controller.diffToggle.state = .on; controller.diffToggleChanged(controller.diffToggle)
    precondition(!controller.detailsPane!.isHidden)
    if let previousDiff { UserDefaults.standard.set(previousDiff, forKey: "showDiff") } else { UserDefaults.standard.removeObject(forKey: "showDiff") }
    // The branch and worktree path sit in the header, beside a narrow search field; every header control fits at the minimum width.
    let header = controller.search.superview as! NSStackView
    precondition(header.arrangedSubviews.contains(controller.currentPathLabel) && header.arrangedSubviews.contains(controller.currentBranchLabel))
    precondition(header.arrangedSubviews.contains { ($0 as? NSButton)?.title == "Open repo…" })
    precondition((header.arrangedSubviews.last as? NSButton)?.action == #selector(Controller.showAbout))
    // About opens one read-only popup (no buttons, no auto-close): name, version, then three paragraphs; the cross closes it.
    let help = controller.showAbout()
    precondition(help.phase == .success && help.panel.sheetParent === window && Controller.aboutText.components(separatedBy: "\n\n").count == 3)
    // Clicking the text starts a selection; it must keep its 14pt font instead of shrinking.
    let helpField = help.infoField!; let helpHeight = helpField.fittingSize.height
    let editor = help.panel.fieldEditor(true, for: helpField) as! NSTextView
    helpField.cell!.select(withFrame: helpField.bounds, in: helpField, editor: editor, delegate: helpField, start: 0, length: 0)
    let editorFont = editor.textStorage!.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    precondition(editorFont?.pointSize == 14, "About text font while selected: \(String(describing: editorFont?.pointSize))")
    let editorStyle = editor.textStorage!.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    precondition(editorStyle?.paragraphSpacing == 12, "About paragraph spacing lost while selected")
    helpField.cell!.endEditing(editor)
    precondition(abs(helpField.fittingSize.height - helpHeight) < 1, "About text height changed on click")
    help.close()
    precondition(controller.currentWorktreeViews.allSatisfy(\.isHidden) == controller.currentPathLabel.stringValue.isEmpty)
    controller.currentBranchLabel.stringValue = "feature/a-very-long-branch-name-for-the-header"
    controller.currentPathLabel.stringValue = "/Users/someone/projects/a/very/long/path/to/the/worktree/folder"
    for view in controller.currentWorktreeViews { view.isHidden = false }
    window.setFrame(NSRect(x: oldFrame.minX, y: oldFrame.minY, width: window.minSize.width, height: 900), display: false)
    window.contentView!.layoutSubtreeIfNeeded()
    precondition(controller.search.frame.width == 130, "Search width \(controller.search.frame.width)")
    precondition(header.arrangedSubviews.last!.frame.maxX <= header.bounds.width, "Header overflows at the minimum width")
    window.setFrame(oldFrame, display: false)
    print("PASS: Pull enabled on local/remote main despite the prod association mismatch; loading still blocks actions")
    print("PASS: one branch menu for every badge zone with a Delete submenu, short typed menus, per-item frequency persistence, legacy counts, disabled guards, full/10-character hashes and exact workspace path; real badge/table right-click routing targets commit/local/remote/tag/worktree correctly")
}
try checkAdaptiveCommitMenu()
