import AppKit
import GitGraphCore

enum HistoryMenuTarget: Equatable {
    case commit
    case reference(String)
    case worktree(String)
}

final class ItemMenuBuilder {
    let menu = NSMenu()
    let kind: ActionItemKind
    let usage: ActionUsage
    private var ids: [CommitActionID] = []
    private var items: [CommitActionID: NSMenuItem] = [:]
    init(kind: ActionItemKind, usage: ActionUsage) { self.kind = kind; self.usage = usage; menu.autoenablesItems = false }
    @discardableResult func add(_ title: String, id: CommitActionID, enabled: Bool = true, _ handler: @escaping () -> Void) -> NSMenuItem {
        let command = MenuCommand(id: id, kind: kind, usage: usage, handler: handler)
        let item = NSMenuItem(title: title, action: #selector(MenuCommand.invoke(_:)), keyEquivalent: "")
        item.target = command; item.representedObject = command; item.isEnabled = enabled
        item.identifier = NSUserInterfaceItemIdentifier(id.rawValue)
        ids.append(id); items[id] = item; return item
    }
    func finish() -> NSMenu {
        for id in usage.ranked(ids, kind: kind) { menu.addItem(items[id]!) }
        return menu
    }
}

extension Controller {
    func itemMenu(at row: Int, target: HistoryMenuTarget) -> NSMenu? {
        guard let repo = repository else { return nil }
        switch target {
        case .commit: return commitMenu(at: row)
        case .reference(let ref):
            if ref.hasPrefix("refs/tags/") { return tagMenu(reference: ref, repo: repo) }
            return branchMenu(reference: ref, repo: repo)
        case .worktree(let path):
            guard let tree = repo.worktrees.first(where: { $0.path == path }) else { return nil }
            return worktreeMenu(tree, repo: repo)
        }
    }
    func canEditCurrent(_ repo: Repository) -> Bool {
        let active = repo.worktrees.first { Git.samePath($0.path, repo.path) }
        return !loading && !operationRunning && repo.pendingOperation == nil && active?.associationIssue == nil && active?.branch != nil
    }
    func commitMenu(at row: Int) -> NSMenu? {
        guard let commit = commit(at: row), let repo = repository else { return nil }
        let menu = ItemMenuBuilder(kind: .commit, usage: actionUsage)
        menu.add("Add Tag…", id: .addTag, enabled: canEditCurrent(repo)) { [weak self] in self?.tagDialog(commit, repo: repo) }
        menu.add("Create Branch", id: .createBranch, enabled: !loading && !operationRunning) { [weak self] in self?.createLocalBranchOnly(start: commit.id) }
        menu.add("Cherry-pick…", id: .cherryPick, enabled: canEditCurrent(repo)) { [weak self] in self?.mainlineDialog(commit, repo: repo, revert: false) }
        menu.add("Copy Full Commit Hash", id: .copyHash) { [weak self] in self?.copyText(commit.id) }
        menu.add("Copy Short Commit Hash", id: .copyShortHash) { [weak self] in self?.copyText(String(commit.id.prefix(10))) }
        return menu.finish()
    }
    func branchMenu(reference: String, repo: Repository) -> NSMenu? {
        guard let ref = repo.references.first(where: { $0.name == reference && !$0.symbolic }),
              let group = repo.branchGroups.first(where: { $0.references.contains(reference) }) else { return nil }
        let menu = ItemMenuBuilder(kind: .branch, usage: actionUsage)
        let name = group.name, local = ref.isBranch
        let tree = repo.worktrees.first { $0.assignedBranch == "refs/heads/" + name || $0.branch == "refs/heads/" + name }
        let ready = !loading && !operationRunning
        let available = tree == nil || tree!.exists && tree!.associationIssue == nil && !tree!.isBare
        let isCurrent = tree.map { Git.samePath($0.path, repo.path) } ?? false
        let origin = ref.isBranch || ref.name.hasPrefix("refs/remotes/origin/")
        menu.add("Open", id: .checkout, enabled: ready && available && !isCurrent) { [weak self] in
            if local { self?.openLocalWorkspace(name, repo: repo) } else { self?.openRemoteWorkspace(ref.name, repo: repo) }
        }.toolTip = "Reuse this branch’s workspace, or create it automatically. Never switch an existing workspace’s branch."
        menu.add("Push to origin", id: .pushBranch, enabled: ready && local) { [weak self] in self?.executeItemAction(.pushBranch(name), repo: repo, title: "Push " + name) }
        let referenceOnlyPull = group.localReference != nil && Git.canPullWithoutEditingWorkspace(name, worktrees: repo.worktrees)
        menu.add("Pull from origin", id: .pullBranch, enabled: ready && origin && (referenceOnlyPull || available && (tree == nil || tree?.changedFiles == 0))) { [weak self] in self?.executeItemAction(.pullBranch(name), repo: repo, title: "Pull " + name) }
            .toolTip = referenceOnlyPull
                ? "Update origin/\(name) and fast-forward local \(name) without touching the workspace currently on another branch."
                : "Fetch only origin/\(name) and fast-forward its dedicated workspace; diverged history is left unchanged."
        menu.add("Rename…", id: .renameBranch, enabled: ready && local && available) { [weak self] in self?.renameBranchDialog(name, repo: repo) }
        let commit = Commit(id: ref.target, parents: [], subject: name)
        menu.add("Merge into \(repo.branch)…", id: .merge, enabled: canEditCurrent(repo) && ref.target != activeHead) { [weak self] in self?.mergeDialog(commit, repo: repo) }
        menu.add("Copy Branch Name", id: .copyBranchName) { [weak self] in self?.copyText(ref.shortName) }
        return menu.finish()
    }
    func tagMenu(reference: String, repo: Repository) -> NSMenu? {
        guard let ref = repo.references.first(where: { $0.name == reference && $0.isTag }) else { return nil }
        let menu = ItemMenuBuilder(kind: .tag, usage: actionUsage)
        menu.add("Delete Local Tag…", id: .deleteTag, enabled: canEditCurrent(repo)) { [weak self] in
            self?.confirmAction("Delete Local Tag", detail: "Delete only \(ref.shortName) in this clone. The remote tag is kept.", repo: repo, action: .deleteTag(ref.shortName), destructive: true)
        }
        menu.add("Publish on origin", id: .pushTag, enabled: !loading && !operationRunning) { [weak self] in self?.executeItemAction(.pushTag(ref.shortName), repo: repo, title: "Publish Tag " + ref.shortName) }
        menu.add("Copy Tag Name", id: .copyTagName) { [weak self] in self?.copyText(ref.shortName) }
        return menu.finish()
    }
    func worktreeMenu(_ tree: GitWorktree, repo: Repository) -> NSMenu {
        let menu = ItemMenuBuilder(kind: .worktree, usage: actionUsage)
        let active = Git.samePath(tree.path, repo.path), ready = !loading && !operationRunning
        menu.add("Open", id: .openWorktree, enabled: ready && tree.exists && !tree.isBare && !active) { [weak self] in
            guard self?.repository?.path == repo.path, self?.operationRunning == false else { return }
            self?.open(tree.path)
        }
        menu.add("Show in Finder", id: .revealWorktree, enabled: tree.exists) { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: tree.path) }
        menu.add("Copy Worktree Path", id: .copyWorktreePath) { [weak self] in self?.copyText(tree.path) }
        menu.add("Delete Worktree…", id: .deleteWorktree, enabled: ready && !active && !tree.isMain && tree.exists && !tree.isLocked && !tree.isBare && tree.changedFiles == 0 && tree.associationIssue == nil) { [weak self] in
            guard let self else { return }
            let alert = NSAlert(); alert.messageText = "Delete Worktree"; alert.informativeText = "Remove \(tree.path). Its branch is kept. Modified, active, main or locked worktrees will not be removed."
            alert.alertStyle = .warning; alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Delete Worktree")
            alert.beginSheetModal(for: self.window!) { [weak self] response in
                guard response == .alertSecondButtonReturn else { return }
                self?.runItem(title: "Delete Worktree", repo: repo) {
                    let current = try Git.worktrees(at: repo.path).first { $0.path == tree.path }
                    guard current?.head == tree.head, current?.branch == tree.branch else { throw GitError(message: "This workspace changed. Refresh before deleting it.") }
                    return ActionResult(output: try Git.performWorktree(.remove(tree.path), at: repo.path), backup: nil)
                }
            }
        }
        return menu.finish()
    }
    func executeItemAction(_ action: RepositoryItemAction, repo: Repository, title: String) {
        runItem(title: title, repo: repo, completion: { [weak self] in
            if case .renameBranch(let old, let new) = action, let self {
                if self.branchPins.remove(old) != nil || old == "main" || old == "master" { self.branchPins.insert(new); self.saveBranchPins() }
                if self.branchSelection?.remove(old) != nil { self.branchSelection?.insert(new) }
            }
        }) { try Git.performItem(action, at: repo.path, expectedSignature: repo.signature) }
    }
    func runItem(title: String, repo: Repository, completion: (() -> Void)? = nil, work: @escaping () throws -> ActionResult) {
        guard !operationRunning, repository?.path == repo.path else { return }
        operationRunning = true; branches.isEnabled = false; more.isEnabled = false; spinner.startAnimation(nil); footer.stringValue = title + "…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try work() }
            DispatchQueue.main.async {
                guard let self else { return }
                self.operationRunning = false; self.branches.isEnabled = true; self.more.isEnabled = true; self.spinner.stopAnimation(nil)
                if case .success = result { completion?() }
                self.refresh(path: repo.path)
                if case .failure(let error) = result { self.showError(error.localizedDescription) }
            }
        }
    }
    @objc func continueCurrentOperation() { recoverCurrentOperation(abort: false) }
    @objc func abortCurrentOperation() { recoverCurrentOperation(abort: true) }
    func recoverCurrentOperation(abort: Bool) {
        guard let repo = repository, let operation = repo.pendingOperation, !operationRunning else { return }
        confirmAction(abort ? "Abort \(operation)" : "Continue \(operation)", detail: abort ? "Abort the pending operation. Conflict-resolution changes may be discarded." : "Resolve conflicts and stage the resolved files before continuing.", repo: repo, action: abort ? .abortOperation(operation) : .continueOperation(operation), destructive: abort)
    }
}

extension Controller: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(continueCurrentOperation) || menuItem.action == #selector(abortCurrentOperation) {
            guard let repo = repository, repo.pendingOperation != nil, !loading, !operationRunning else { return false }
            let active = repo.worktrees.first { Git.samePath($0.path, repo.path) }
            return active?.associationIssue == nil && active?.assignedBranch != nil
        }
        return true
    }
}
