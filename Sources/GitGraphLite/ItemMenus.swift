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
    private var entries: [(id: CommitActionID?, item: NSMenuItem, gap: Bool)] = []
    private var pendingSeparator = false
    init(kind: ActionItemKind, usage: ActionUsage, fixedOrder: Bool = false) { self.kind = kind; self.usage = usage; self.fixedOrder = fixedOrder; menu.autoenablesItems = false }
    func addSeparator() { if !entries.isEmpty { pendingSeparator = true } }
    @discardableResult func add(_ title: String, id: CommitActionID, enabled: Bool = true, _ handler: @escaping () -> Void) -> NSMenuItem {
        let command = MenuCommand(id: id, kind: kind, usage: usage, handler: handler)
        let item = NSMenuItem(title: title, action: #selector(MenuCommand.invoke(_:)), keyEquivalent: "")
        item.target = command; item.representedObject = command; item.isEnabled = enabled
        item.identifier = NSUserInterfaceItemIdentifier(id.rawValue)
        entries.append((id, item, pendingSeparator)); pendingSeparator = false
        return item
    }
    /// A titled submenu, kept in fixed order; it is greyed when none of its items can run.
    @discardableResult func addSubmenu(_ title: String, _ fill: (ItemMenuBuilder) -> Void) -> NSMenuItem {
        let child = ItemMenuBuilder(kind: kind, usage: usage, fixedOrder: true); fill(child)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: ""); item.submenu = child.finish()
        item.isEnabled = item.submenu!.items.contains { $0.isEnabled && !$0.isSeparatorItem }
        entries.append((nil, item, pendingSeparator)); pendingSeparator = false
        return item
    }
    func finish() -> NSMenu {
        if fixedOrder {
            for entry in entries { if entry.gap { menu.addItem(.separator()) }; menu.addItem(entry.item) }
        } else {
            var byID: [CommitActionID: NSMenuItem] = [:]
            for entry in entries { if let id = entry.id { byID[id] = entry.item } }
            for id in usage.ranked(entries.compactMap(\.id), kind: kind) { menu.addItem(byID[id]!) }
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
        case .localBranch(let ref), .remoteBranch(let ref): return branchMenu(reference: ref, repo: repo)
        case .worktree(let path):
            guard let tree = repo.worktrees.first(where: { $0.path == path }) else { return nil }
            if let branch = tree.branch ?? tree.assignedBranch, let menu = branchMenu(reference: branch, repo: repo) { return menu }
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
    /// One menu for every part of a branch badge (name, computer, cloud, worktree icon).
    /// Open Branch (creating its worktree if needed), merge, sync, rename, a Delete submenu (local + origin, local, remote, worktree), copies.
    func branchMenu(reference: String, repo: Repository) -> NSMenu? {
        guard let (ref, name, tree, isCurrent, ready) = branchContext(reference, repo: repo) else { return nil }
        let menu = ItemMenuBuilder(kind: .branch, usage: actionUsage, fixedOrder: true)
        let localRef = repo.references.first { $0.name == "refs/heads/" + name }
        let originRef = repo.references.first { $0.name == "refs/remotes/origin/" + name }
        // The cloud that was clicked picks the remote for Delete on Remote; otherwise origin.
        let remote = ref.name.hasPrefix("refs/remotes/") ? String(ref.shortName.prefix { $0 != "/" }) : "origin"
        let remoteRef = repo.references.first { $0.name == "refs/remotes/\(remote)/" + name }
        let available = tree == nil || tree!.exists && tree!.associationIssue == nil && !tree!.isBare

        // Every local branch in use lives in its own worktree: Open Branch switches the window to it,
        // creating the worktree first (in a popup) when the branch has none yet.
        menu.add("Open Branch", id: .openBranch, enabled: ready && !isCurrent && available) { [weak self] in
            guard let self, self.repository?.path == repo.path, !self.operationRunning else { return }
            if let tree { self.open(tree.path, focusHead: true); return }
            var made: String?
            self.actionPopup("Open Branch", detail: "No worktree yet: creating one for this branch, then opening it.", facts: [.init(label: "Branch", value: name)], running: "Creating worktree for \(name)", git: repo, then: { [weak self] in
                if let made { self?.open(made, focusHead: true) }
            }) {
                let result = localRef != nil ? try Git.openLocalBranch(name, at: repo.path, expectedSignature: repo.signature)
                    : try Git.openRemoteBranch((originRef ?? ref).name, at: repo.path, expectedSignature: repo.signature)
                made = result.path
                return ("Worktree created, branch opened.", [.init(label: "Branch", value: result.branch), .init(label: "New worktree", value: result.path)], "")
            }
        }
        let commit = Commit(id: ref.target, parents: [], subject: name)
        menu.add("Merge into Current", id: .merge, enabled: canEditCurrent(repo) && !isCurrent && ref.target != activeHead) { [weak self] in self?.mergeDialog(commit, repo: repo) }
        menu.addSeparator()

        menu.add("Push", id: .pushBranch, enabled: ready && localRef != nil && originRef?.target != localRef?.target) { [weak self] in
            self?.actionPopup("Push", facts: [.init(label: "Branch", value: name), .init(label: "To", value: "origin")], running: "Pushing", git: repo) {
                let result = try Git.performItem(.pushBranch(name), at: repo.path, expectedSignature: repo.signature)
                return ("Pushed to origin.", nil, result.output)
            }
        }
        let referenceOnlyPull = localRef != nil && Git.canPullWithoutEditingWorkspace(name, worktrees: repo.worktrees)
        let canPull = originRef != nil && localRef?.target != originRef?.target && (referenceOnlyPull || available && (tree == nil || tree?.changedFiles == 0))
        menu.add("Pull", id: .pullBranch, enabled: ready && canPull) { [weak self] in
            self?.actionPopup("Pull", facts: [.init(label: "Branch", value: name), .init(label: "From", value: "origin")], running: "Pulling", git: repo) {
                let result = try Git.performItem(.pullBranch(name), at: repo.path, expectedSignature: repo.signature)
                return ("Pulled from origin.", nil, result.output)
            }
        }
        menu.addSeparator()

        menu.add("Rename…", id: .renameBranch, enabled: ready && localRef != nil && available) { [weak self] in self?.renameBranchDialog(name, repo: repo) }
        // Every delete asks for confirmation in its popup; an unmerged local branch offers Delete Anyway.
        let unmerged: (String) -> Bool = { $0.contains("not fully merged") }
        let noTree = ready && tree == nil && !isCurrent
        menu.addSubmenu("Delete") { sub in
            sub.add("Local + Origin", id: .deleteBranchEverywhere, enabled: noTree && localRef != nil && originRef != nil) { [weak self] in
                self?.actionPopup("Delete Branch", facts: [.init(label: "Branch", value: name), .init(label: "From", value: "local + origin")], confirm: "Delete", running: "Deleting branch", git: repo,
                    fallback: PopupFallback(title: "Delete Anyway", when: unmerged) {
                        (try Git.performItem(.deleteBranchEverywhere(name, force: true), at: repo.path).output, nil, "")
                    }) {
                        (try Git.performItem(.deleteBranchEverywhere(name, force: false), at: repo.path, expectedSignature: repo.signature).output, nil, "")
                    }
            }
            sub.add("Local Branch", id: .deleteBranch, enabled: noTree && localRef != nil) { [weak self] in
                self?.actionPopup("Delete Local Branch", facts: [.init(label: "Branch", value: name)], confirm: "Delete", running: "Deleting branch", git: repo,
                    fallback: PopupFallback(title: "Delete Anyway", when: unmerged) {
                        _ = try Git.performItem(.deleteLocalBranch(name, force: true), at: repo.path)
                        return ("Local branch deleted.", nil, "")
                    }) {
                        (try Git.performItem(.deleteLocalBranch(name, force: false), at: repo.path, expectedSignature: repo.signature).output, nil, "")
                    }
            }
            sub.add("On \(remote)", id: .deleteRemoteBranch, enabled: ready && remoteRef != nil) { [weak self] in
                self?.actionPopup("Delete on Remote", facts: [.init(label: "Branch", value: "\(remote)/\(name)")], confirm: "Delete", running: "Deleting on \(remote)", git: repo) {
                    (try Git.performItem(.deleteRemoteBranch(remote: remote, branch: name), at: repo.path, expectedSignature: repo.signature).output, nil, "")
                }
            }
            sub.add("Worktree", id: .deleteWorktree, enabled: tree.map { canDeleteWorktree($0, repo: repo) } ?? false) { [weak self] in
                if let tree { self?.deleteWorktreePopup(tree, repo: repo) }
            }
        }
        menu.addSeparator()
        menu.add("Copy Branch Name", id: .copyBranchName) { [weak self] in self?.copyPopup("Branch", name) }
        menu.add("Copy Worktree Path", id: .copyWorktreePath, enabled: tree != nil) { [weak self] in if let tree { self?.copyPopup("Path", tree.path) } }
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
    /// The worktree icon: Open Worktree, Delete Worktree (confirmed in its popup; the branch is kept), Copy Path.
    func worktreeMenu(_ tree: GitWorktree, repo: Repository) -> NSMenu {
        let menu = ItemMenuBuilder(kind: .worktree, usage: actionUsage, fixedOrder: true)
        let active = Git.samePath(tree.path, repo.path), ready = !loading && !operationRunning
        // Opening only switches the window to that folder, so it acts at once instead of through a popup.
        menu.add("Open Worktree", id: .openWorktree, enabled: ready && tree.exists && !tree.isBare && !active) { [weak self] in
            guard self?.repository?.path == repo.path, self?.operationRunning == false else { return }
            self?.open(tree.path)
        }
        menu.addSeparator()
        menu.add("Delete Worktree", id: .deleteWorktree, enabled: canDeleteWorktree(tree, repo: repo)) { [weak self] in self?.deleteWorktreePopup(tree, repo: repo) }
        menu.addSeparator()
        menu.add("Copy Worktree Path", id: .copyWorktreePath) { [weak self] in self?.copyPopup("Path", tree.path) }
        return menu.finish()
    }
    func canDeleteWorktree(_ tree: GitWorktree, repo: Repository) -> Bool {
        !loading && !operationRunning && !tree.isMain && tree.exists && !tree.isLocked && !tree.isBare && tree.changedFiles == 0 && tree.associationIssue == nil
    }
    /// Confirmed in the popup; the branch is kept. Deleting the displayed worktree runs Git from
    /// the main worktree, then switches the window there.
    func deleteWorktreePopup(_ tree: GitWorktree, repo: Repository) {
        let displayed = Git.samePath(tree.path, repo.path)
        guard let main = repo.worktrees.first(where: \.isMain)?.path ?? (displayed ? nil : repo.path) else { return }
        var facts: [ActionPopup.Fact] = [.init(label: "Folder", value: tree.path)]
        if let branch = tree.branch { facts.append(.init(label: "Branch kept", value: branch.hasPrefix("refs/heads/") ? String(branch.dropFirst(11)) : branch)) }
        actionPopup("Delete Worktree", detail: displayed ? "This is the worktree shown in the window: it then switches to the main worktree." : "", facts: facts, confirm: "Delete", running: "Deleting worktree", git: repo,
            then: displayed ? { [weak self] in self?.open(main, focusHead: true) } : nil) {
            let current = try Git.worktrees(at: main).first { Git.samePath($0.path, tree.path) }
            guard current?.head == tree.head, current?.branch == tree.branch else { throw GitError(message: "This worktree changed. Refresh before deleting it.") }
            _ = try Git.performWorktree(.remove(tree.path), at: main)
            return ("Worktree deleted.", [.init(label: "Folder", value: tree.path)], "")
        }
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
