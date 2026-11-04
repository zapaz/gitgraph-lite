import AppKit
import GitGraphCore

/// The name of a branch or tag targets `reference`; the computer and cloud icons of a branch badge have their own menus.
enum HistoryMenuTarget: Equatable {
    case commit
    case reference(String)
    case localBranch(String)
    case remoteBranch(String)
    case worktree(String)
}

final class ItemMenuBuilder {
    let menu = NSMenu()
    let kind: ActionItemKind
    let usage: ActionUsage
    /// A fixed menu keeps the order it was built in, with its separators, instead of ranking items by use.
    let fixedOrder: Bool
    private var ids: [CommitActionID] = []
    private var items: [CommitActionID: NSMenuItem] = [:]
    private var separatorsBefore = Set<CommitActionID>()
    private var pendingSeparator = false
    init(kind: ActionItemKind, usage: ActionUsage, fixedOrder: Bool = false) { self.kind = kind; self.usage = usage; self.fixedOrder = fixedOrder; menu.autoenablesItems = false }
    func addSeparator() { if !ids.isEmpty { pendingSeparator = true } }
    @discardableResult func add(_ title: String, id: CommitActionID, enabled: Bool = true, _ handler: @escaping () -> Void) -> NSMenuItem {
        let command = MenuCommand(id: id, kind: kind, usage: usage, handler: handler)
        let item = NSMenuItem(title: title, action: #selector(MenuCommand.invoke(_:)), keyEquivalent: "")
        item.target = command; item.representedObject = command; item.isEnabled = enabled
        item.identifier = NSUserInterfaceItemIdentifier(id.rawValue)
        if pendingSeparator { separatorsBefore.insert(id); pendingSeparator = false }
        ids.append(id); items[id] = item; return item
    }
    func finish() -> NSMenu {
        for id in fixedOrder ? ids : usage.ranked(ids, kind: kind) {
            if fixedOrder, separatorsBefore.contains(id) { menu.addItem(.separator()) }
            menu.addItem(items[id]!)
        }
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
        case .localBranch(let ref): return localBranchMenu(reference: ref, repo: repo)
        case .remoteBranch(let ref): return remoteBranchMenu(reference: ref, repo: repo)
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
        let menu = ItemMenuBuilder(kind: .commit, usage: actionUsage, fixedOrder: true)
        menu.add("Add Tag…", id: .addTag, enabled: canEditCurrent(repo)) { [weak self] in self?.tagDialog(commit, repo: repo) }
        menu.add("Create Branch…", id: .createBranch, enabled: !loading && !operationRunning) { [weak self] in self?.createBranchDialog(commit, repo: repo) }
        menu.addSeparator()
        menu.add("Cherry Pick…", id: .cherryPick, enabled: canEditCurrent(repo)) { [weak self] in self?.mainlineDialog(commit, repo: repo, revert: false) }
        menu.addSeparator()
        menu.add("Copy Hash", id: .copyHash) { [weak self] in self?.copyPopup("Hash", commit.id) }
        menu.add("Copy Short Hash", id: .copyShortHash) { [weak self] in self?.copyPopup("Short hash", String(commit.id.prefix(10))) }
        menu.add("Copy Subject", id: .copySubject) { [weak self] in self?.copyPopup("Subject", commit.subject) }
        return menu.finish()
    }
    private func branchContext(_ reference: String, repo: Repository) -> (ref: GitReference, name: String, tree: GitWorktree?, isCurrent: Bool, ready: Bool)? {
        guard let ref = repo.references.first(where: { $0.name == reference && !$0.symbolic }),
              let group = repo.branchGroups.first(where: { $0.references.contains(reference) }) else { return nil }
        let name = group.name
        let tree = repo.worktrees.first { $0.assignedBranch == "refs/heads/" + name || $0.branch == "refs/heads/" + name }
        let isCurrent = tree.map { Git.samePath($0.path, repo.path) } ?? false
        return (ref, name, tree, isCurrent, !loading && !operationRunning)
    }
    /// The branch itself: Create Worktree, Merge into Current, Rename, Delete Branch (local and origin), Copy Name.
    func branchMenu(reference: String, repo: Repository) -> NSMenu? {
        guard let (ref, name, tree, isCurrent, ready) = branchContext(reference, repo: repo) else { return nil }
        let menu = ItemMenuBuilder(kind: .branch, usage: actionUsage, fixedOrder: true)
        let local = ref.isBranch
        menu.add("Create Worktree", id: .createWorktree, enabled: ready && tree == nil) { [weak self] in
            self?.actionPopup("Create Worktree", facts: [.init(label: "Branch", value: name)], running: "Creating worktree", git: repo) {
                let made = local ? try Git.openLocalBranch(name, at: repo.path, expectedSignature: repo.signature) : try Git.openRemoteBranch(ref.name, at: repo.path, expectedSignature: repo.signature)
                return ("Worktree created.", [.init(label: "Branch", value: made.branch), .init(label: "Folder", value: made.path)], "")
            }
        }
        let commit = Commit(id: ref.target, parents: [], subject: name)
        menu.add("Merge into Current", id: .merge, enabled: canEditCurrent(repo) && !isCurrent && ref.target != activeHead) { [weak self] in self?.mergeDialog(commit, repo: repo) }
        menu.addSeparator()
        let available = tree == nil || tree!.exists && tree!.associationIssue == nil && !tree!.isBare
        menu.add("Rename…", id: .renameBranch, enabled: ready && local && available) { [weak self] in self?.renameBranchDialog(name, repo: repo) }
        // Local and origin together. It reaches a shared remote, so the popup asks first.
        let onOrigin = repo.references.contains { $0.name == "refs/remotes/origin/" + name }
        let hasLocal = repo.references.contains { $0.name == "refs/heads/" + name }
        menu.add("Delete Branch", id: .deleteBranchEverywhere, enabled: ready && tree == nil && !isCurrent && (hasLocal || onOrigin)) { [weak self] in
            let places = [hasLocal ? "local" : nil, onOrigin ? "origin" : nil].compactMap { $0 }.joined(separator: " + ")
            self?.actionPopup("Delete Branch", facts: [.init(label: "Branch", value: name), .init(label: "From", value: places)], confirm: "Delete", running: "Deleting branch", git: repo,
                fallback: PopupFallback(title: "Delete Anyway", when: { $0.contains("not fully merged") }) {
                    (try Git.performItem(.deleteBranchEverywhere(name, force: true), at: repo.path).output, nil, "")
                }) {
                    (try Git.performItem(.deleteBranchEverywhere(name, force: false), at: repo.path, expectedSignature: repo.signature).output, nil, "")
                }
        }
        menu.addSeparator()
        menu.add("Copy Name", id: .copyBranchName) { [weak self] in self?.copyPopup("Branch", ref.shortName) }
        return menu.finish()
    }
    /// The local branch: Push (only while origin is not at the same commit), Delete Local Branch, Copy Name.
    func localBranchMenu(reference: String, repo: Repository) -> NSMenu? {
        guard let (ref, name, tree, isCurrent, ready) = branchContext(reference, repo: repo), ref.isBranch else { return nil }
        let menu = ItemMenuBuilder(kind: .branch, usage: actionUsage, fixedOrder: true)
        let synced = repo.references.contains { $0.name == "refs/remotes/origin/" + name && $0.target == ref.target }
        menu.add("Push", id: .pushBranch, enabled: ready && !synced) { [weak self] in
            self?.actionPopup("Push", facts: [.init(label: "Branch", value: name), .init(label: "To", value: "origin")], running: "Pushing", git: repo) {
                let result = try Git.performItem(.pushBranch(name), at: repo.path, expectedSignature: repo.signature)
                return ("Pushed to origin.", nil, result.output)
            }
        }
        menu.addSeparator()
        menu.add("Delete Local Branch", id: .deleteBranch, enabled: ready && tree == nil && !isCurrent) { [weak self] in
            // No confirmation: Git refuses an unmerged branch, and the popup then offers Delete Anyway.
            self?.actionPopup("Delete Local Branch", facts: [.init(label: "Branch", value: name)], confirm: "Delete", running: "Deleting branch", git: repo,
                fallback: PopupFallback(title: "Delete Anyway", when: { $0.contains("not fully merged") }) {
                    _ = try Git.performItem(.deleteLocalBranch(name, force: true), at: repo.path)
                    return ("Local branch deleted.", nil, "")
                }) {
                    let result = try Git.performItem(.deleteLocalBranch(name, force: false), at: repo.path, expectedSignature: repo.signature)
                    return (result.output, nil, "")
                }
        }
        menu.addSeparator()
        menu.add("Copy Name", id: .copyBranchName) { [weak self] in self?.copyPopup("Branch", name) }
        return menu.finish()
    }
    /// The branch on one remote: Pull (only while the local branch is not at the same commit), Delete on Remote, Copy Name.
    func remoteBranchMenu(reference: String, repo: Repository) -> NSMenu? {
        guard let (ref, name, tree, _, ready) = branchContext(reference, repo: repo), ref.name.hasPrefix("refs/remotes/") else { return nil }
        let remote = String(ref.shortName.prefix { $0 != "/" })
        let menu = ItemMenuBuilder(kind: .branch, usage: actionUsage, fixedOrder: true)
        let localRef = repo.references.first { $0.name == "refs/heads/" + name }
        let available = tree == nil || tree!.exists && tree!.associationIssue == nil && !tree!.isBare
        let referenceOnlyPull = localRef != nil && Git.canPullWithoutEditingWorkspace(name, worktrees: repo.worktrees)
        let canPull = remote == "origin" && localRef?.target != ref.target && (referenceOnlyPull || available && (tree == nil || tree?.changedFiles == 0))
        menu.add("Pull", id: .pullBranch, enabled: ready && canPull) { [weak self] in
            self?.actionPopup("Pull", facts: [.init(label: "Branch", value: name), .init(label: "From", value: remote)], running: "Pulling", git: repo) {
                let result = try Git.performItem(.pullBranch(name), at: repo.path, expectedSignature: repo.signature)
                return ("Pulled from \(remote).", nil, result.output)
            }
        }.toolTip = remote == "origin" ? nil : "Pull works with origin only."
        menu.addSeparator()
        // A shared remote branch may hold other people's work: the popup asks before deleting it.
        menu.add("Delete on Remote", id: .deleteRemoteBranch, enabled: ready) { [weak self] in
            self?.actionPopup("Delete on Remote", facts: [.init(label: "Branch", value: ref.shortName)], confirm: "Delete", running: "Deleting on \(remote)", git: repo) {
                let result = try Git.performItem(.deleteRemoteBranch(remote: remote, branch: name), at: repo.path, expectedSignature: repo.signature)
                return (result.output, nil, "")
            }
        }
        menu.addSeparator()
        menu.add("Copy Name", id: .copyBranchName) { [weak self] in self?.copyPopup("Branch", ref.shortName) }
        return menu.finish()
    }
    func tagMenu(reference: String, repo: Repository) -> NSMenu? {
        guard let ref = repo.references.first(where: { $0.name == reference && $0.isTag }) else { return nil }
        let menu = ItemMenuBuilder(kind: .tag, usage: actionUsage)
        // No confirmation: the popup shows progress and where the tag was deleted.
        menu.add("Delete Tag", id: .deleteTag, enabled: !loading && !operationRunning) { [weak self] in
            self?.actionPopup("Delete Tag", facts: [.init(label: "Tag", value: ref.shortName)], confirm: "Delete", running: "Deleting tag", git: repo) {
                let result = try Git.performItem(.deleteTagEverywhere(ref.shortName), at: repo.path, expectedSignature: repo.signature)
                return (result.output, nil, "")
            }
        }
        menu.add("Push", id: .pushTag, enabled: !loading && !operationRunning) { [weak self] in
            self?.actionPopup("Push Tag", facts: [.init(label: "Tag", value: ref.shortName)], running: "Pushing tag", git: repo) {
                let result = try Git.performItem(.pushTagEverywhere(ref.shortName), at: repo.path, expectedSignature: repo.signature)
                return (result.output, nil, "")
            }
        }
        menu.add("Copy Name", id: .copyTagName) { [weak self] in self?.copyPopup("Tag", ref.shortName) }
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
