import AppKit
import GitGraphCore

final class CommitTableView: NSTableView {
    var menuProvider: ((Int, String?) -> NSMenu?)?
    override func menu(for event: NSEvent) -> NSMenu? {
        let index = row(at: convert(event.locationInWindow, from: nil))
        guard index >= 0 else { return nil }
        var reference: String?
        if let column = tableColumns.firstIndex(where: { $0.identifier.rawValue == "subject" }), let cell = view(atColumn: column, row: index, makeIfNecessary: false) as? CommitCell {
            reference = cell.reference(at: cell.convert(event.locationInWindow, from: nil))
        }
        if !selectedRowIndexes.contains(index) { selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
        return menuProvider?(index, reference)
    }
}

final class MenuCommand: NSObject {
    let id: CommitActionID
    let context: String?
    let usage: ActionUsage
    let handler: () -> Void
    init(id: CommitActionID, context: String? = nil, usage: ActionUsage, handler: @escaping () -> Void) {
        self.id = id; self.context = context; self.usage = usage; self.handler = handler
    }
    @objc func invoke(_ sender: Any?) {
        guard (sender as? NSMenuItem)?.isEnabled != false else { return }
        usage.record(id)
        handler()
    }
}

extension Controller {
    func commitMenu(at row: Int, reference: String? = nil) -> NSMenu? {
        guard let commit = commit(at: row), let repo = repository else { return nil }
        let menu = NSMenu(); menu.autoenablesItems = false
        @discardableResult func add(_ title: String, id: CommitActionID, to parent: NSMenu? = nil, enabled: Bool = true, _ handler: @escaping () -> Void) -> NSMenuItem {
            let command = MenuCommand(id: id, context: parent?.title, usage: actionUsage, handler: handler)
            let item = NSMenuItem(title: title, action: #selector(MenuCommand.invoke(_:)), keyEquivalent: "")
            item.target = command; item.representedObject = command; item.isEnabled = enabled
            item.identifier = NSUserInterfaceItemIdentifier(id.rawValue)
            (parent ?? menu).addItem(item)
            return item
        }
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let sub = NSMenu(title: title); sub.autoenablesItems = false; item.submenu = sub; menu.addItem(item); return sub
        }
        let canWrite = !loading && !operationRunning && repo.pendingOperation == nil
        let canOpenWorktree = !loading && !operationRunning
        let current = repo.branch

        add("Add Tag...", id: .addTag, enabled: canWrite) { [weak self] in self?.tagDialog(commit, repo: repo) }
        add("Create Branch...", id: .createBranch, enabled: canOpenWorktree) { [weak self] in
            self?.manageWorktrees(start: commit.id)
        }.toolTip = "Create the new branch in a separate worktree. The current folder stays on its branch."
        menu.addItem(.separator())
        add("Checkout...", id: .checkout, enabled: canOpenWorktree) { [weak self] in self?.checkoutWorktree(commit, repo: repo, reference: reference) }
            .toolTip = "Remote branches check out their same-named local branch here. Local branches open or create their worktree."
        add("Cherry Pick...", id: .cherryPick, enabled: canWrite) { [weak self] in self?.mainlineDialog(commit, repo: repo, revert: false) }
        add("Revert...", id: .revert, enabled: canWrite) { [weak self] in self?.mainlineDialog(commit, repo: repo, revert: true) }
        menu.addItem(.separator())
        add("Merge into current branch...", id: .merge, enabled: canWrite) { [weak self] in self?.mergeDialog(commit, repo: repo) }
        add("Rebase current branch on this Commit...", id: .rebase, enabled: canWrite) { [weak self] in
            self?.confirmAction("Rebase Current Branch", detail: "Rebase \(current) onto \(commit.id.prefix(8)). This rewrites commit hashes and preserves merge structure. A backup branch will save the previous HEAD. A clean working tree is required.", repo: repo, action: .rebase(commit.id), destructive: true)
        }
        add("Reset current branch to this Commit...", id: .reset, enabled: canWrite) { [weak self] in self?.resetDialog(commit, repo: repo) }
        menu.addItem(.separator())
        add("Copy Commit Hash to Clipboard", id: .copyHash) { [weak self] in self?.copyText(commit.id) }
        add("Copy Commit Subject to Clipboard", id: .copySubject) { [weak self] in self?.copyText(commit.subject) }

        do {
            menu.addItem(.separator())
            add("Copy Full Commit Message", id: .copyMessage) { [weak self] in
                self?.readFromRepository(repo.path) { try Git.message(at: repo.path, commit: commit.id) } completion: { text in self?.copyText(text) }
            }
            add("Compare with HEAD", id: .compareHead) { [weak self] in
                self?.readFromRepository(repo.path) { try Git.string(["rev-parse", "HEAD"], at: repo.path) } completion: { head in self?.showDetails(for: commit, base: head) }
            }
            add("Select for Comparison", id: .selectComparison) { [weak self] in self?.comparisonAnchor = commit; self?.footer.stringValue = "Right-click another commit to compare with \(commit.id.prefix(8))." }
            if let anchor = comparisonAnchor, anchor.id != commit.id {
                add("Compare with \(anchor.id.prefix(8))", id: .compareAnchor) { [weak self] in self?.showDetails(for: commit, base: anchor.id) }
            }
            let selected = table.selectedRowIndexes.compactMap { self.commit(at: $0) }
            if selected.count == 2 { add("Compare Selected Commits", id: .compareSelected) { [weak self] in self?.showDetails(for: selected[0], base: selected[1].id) } }
            add("Create Worktree Here...", id: .createWorktree, enabled: canOpenWorktree) { [weak self] in self?.manageWorktrees(start: commit.id) }
            add("Drop Commit...", id: .drop, enabled: canWrite && commit.parents.count == 1) { [weak self] in
                self?.confirmAction("Drop Commit", detail: "Remove \(commit.id.prefix(8)) from the current branch's history and replay its descendants. This rewrites commit hashes. The commit must be an ancestor of \(current). A backup branch will save the previous HEAD.", repo: repo, action: .drop(commit.id), destructive: true)
            }
            for ref in repo.references where ref.target == commit.id && !ref.symbolic {
                let remote = ref.name.hasPrefix("refs/remotes/")
                guard ref.isBranch || ref.isTag || remote else { continue }
                let sub = submenu((remote ? "Remote Branch: " : ref.isBranch ? "Branch: " : "Tag: ") + ref.shortName)
                if remote {
                    add("Checkout \(ref.shortName) in This Worktree", id: .checkoutRemote, to: sub, enabled: canWrite) { [weak self] in
                        self?.navigateRepository(title: "Checking out " + ref.shortName, repo: repo) { try Git.checkoutRemote(ref.name, at: repo.path, expectedSignature: repo.signature) }
                    }
                    add("Copy Branch Name", id: .copyBranchName, to: sub) { [weak self] in self?.copyText(ref.shortName) }
                } else if ref.isBranch {
                    let occupied = repo.worktrees.first { $0.branch == ref.name }
                    if let occupied {
                        let active = Git.samePath(occupied.path, repo.path)
                        add(active ? "Current Worktree: \(occupied.name)" : "Open Worktree: \(occupied.name)", id: .openWorktree, to: sub, enabled: occupied.exists && !operationRunning && !active) { [weak self] in self?.open(occupied.path) }
                    } else {
                        add("Create Worktree on This Branch…", id: .createBranchWorktree, to: sub, enabled: !loading && !operationRunning) { [weak self] in self?.manageWorktrees(start: commit.id, branch: ref.shortName) }
                    }
                    add("Copy Branch Name", id: .copyBranchName, to: sub) { [weak self] in self?.copyText(ref.shortName) }
                    add("Rename Branch…", id: .renameBranch, to: sub, enabled: canWrite && occupied == nil) { [weak self] in self?.renameBranchDialog(ref.shortName, repo: repo) }
                    add("Delete Branch…", id: .deleteBranch, to: sub, enabled: canWrite && ref.shortName != current && occupied == nil) { [weak self] in
                        self?.confirmAction("Delete Branch", detail: "Delete local branch \(ref.shortName). Git will refuse if it contains unmerged work. The branch will not be deleted from any remote.", repo: repo, action: .deleteBranch(ref.shortName), destructive: true)
                    }
                } else {
                    add("Copy Tag Name", id: .copyTagName, to: sub) { [weak self] in self?.copyText(ref.shortName) }
                    add("Delete Tag…", id: .deleteTag, to: sub, enabled: canWrite) { [weak self] in
                        self?.confirmAction("Delete Tag", detail: "Delete local tag \(ref.shortName). The tag will not be deleted from any remote.", repo: repo, action: .deleteTag(ref.shortName), destructive: true)
                    }
                }
            }
        }
        if let operation = repo.pendingOperation {
            menu.addItem(.separator())
            add("Continue \(operation.capitalized)…", id: .continueOperation, enabled: !operationRunning) { [weak self] in
                self?.confirmAction("Continue \(operation.capitalized)", detail: "Resolve conflicts in your editor and stage the resolved files first, then continue the pending \(operation).", repo: repo, action: .continueOperation(operation))
            }
            add("Abort \(operation.capitalized)…", id: .abortOperation, enabled: !operationRunning) { [weak self] in
                self?.confirmAction("Abort \(operation.capitalized)", detail: "Abort the pending \(operation) and return to its previous state. Conflict-resolution work may be discarded.", repo: repo, action: .abortOperation(operation), destructive: true)
            }
        }
        return compactCommitMenu(menu)
    }

    func compactCommitMenu(_ full: NSMenu) -> NSMenu {
        var items: [CommitActionID: [NSMenuItem]] = [:]
        func collect(_ menu: NSMenu) {
            for item in menu.items {
                if let sub = item.submenu { collect(sub) }
                else if let command = item.representedObject as? MenuCommand {
                    menu.removeItem(item)
                    items[command.id, default: []].append(item)
                }
            }
        }
        collect(full)
        let result = NSMenu(); result.autoenablesItems = false
        let more = NSMenu(); more.autoenablesItems = false
        for (index, id) in actionUsage.ranked(Array(items.keys)).enumerated() {
            let choices = items[id]!
            let item: NSMenuItem
            if choices.count == 1 {
                item = choices[0]
                if let command = item.representedObject as? MenuCommand, let context = command.context {
                    item.title += " — " + context
                }
            } else {
                // One ranked action, several possible refs: keep targets explicit without taking several top-five slots.
                item = NSMenuItem(title: id.title, action: nil, keyEquivalent: "")
                item.identifier = NSUserInterfaceItemIdentifier(id.rawValue)
                let targets = NSMenu(title: id.title); targets.autoenablesItems = false
                for choice in choices {
                    if let command = choice.representedObject as? MenuCommand, let context = command.context { choice.title = context }
                    targets.addItem(choice)
                }
                item.submenu = targets; item.isEnabled = choices.contains { $0.isEnabled }
            }
            (index < 5 ? result : more).addItem(item)
        }
        if !more.items.isEmpty {
            result.addItem(.separator())
            let extra = NSMenuItem(title: "Plus…", action: nil, keyEquivalent: ""); extra.submenu = more; result.addItem(extra)
        }
        return result
    }

    func copyText(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }

    func readFromRepository(_ path: String, work: @escaping () throws -> String, completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try work() }
            DispatchQueue.main.async {
                guard let self, self.repository?.path == path else { return }
                switch result { case .success(let text): completion(text); case .failure(let error): self.showError(error.localizedDescription) }
            }
        }
    }

    func showError(_ text: String) {
        let alert = NSAlert(); alert.alertStyle = .warning; alert.messageText = "Git action could not finish"; alert.informativeText = text
        alert.beginSheetModal(for: window!)
    }

    func confirmAction(_ title: String, detail: String, repo: Repository, action: GitAction, destructive: Bool = false) {
        guard !operationRunning else { return }
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail
        alert.alertStyle = destructive ? .warning : .informational
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: title)
        alert.beginSheetModal(for: window!) { [weak self] response in
            if response == .alertSecondButtonReturn { self?.execute(action, repo: repo, title: title) }
        }
    }

    func execute(_ action: GitAction, repo: Repository, title: String) {
        guard !operationRunning, repository?.path == repo.path else { return }
        operationRunning = true; spinner.startAnimation(nil); branches.isEnabled = false; more.isEnabled = false
        footer.stringValue = title + "…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try Git.perform(action, at: repo.path, expectedSignature: repo.signature) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.operationRunning = false; self.spinner.stopAnimation(nil); self.branches.isEnabled = true; self.more.isEnabled = true
                self.refresh(path: repo.path)
                switch result {
                case .success(let value):
                    let alert = NSAlert(); alert.messageText = title + " completed"
                    let summary = value.output.isEmpty ? "The graph has been refreshed." : String(value.output.prefix(3000))
                    alert.informativeText = summary + (value.backup.map { "\n\nPrevious HEAD saved as branch \($0)." } ?? "")
                    alert.beginSheetModal(for: self.window!)
                case .failure(let error): self.showError(error.localizedDescription)
                }
            }
        }
    }

    func inputForm(_ title: String, detail: String, controls: [NSView]) -> NSAlert {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: title)
        let form = NSStackView(views: controls); form.orientation = .vertical; form.alignment = .leading; form.spacing = 10
        form.frame = NSRect(x: 0, y: 0, width: 420, height: CGFloat(controls.count)*34)
        for control in controls { control.widthAnchor.constraint(equalTo: form.widthAnchor).isActive = true }
        alert.accessoryView = form; return alert
    }
    func nameField(_ placeholder: String, value: String = "") -> NSTextField {
        let field = NSTextField(string: value); field.placeholderString = placeholder; return field
    }
    func createAutomaticWorktree(start: String = "HEAD", branch: String? = nil) {
        guard let repo = repository else { return }
        navigateRepository(title: "Creating worktree", repo: repo) { try Git.automaticWorktree(at: repo.path, start: start, branch: branch) }
    }
    func navigateRepository(title: String, repo: Repository, work: @escaping () throws -> NavigationResult) {
        guard !operationRunning, repository?.path == repo.path else { return }
        operationRunning = true; spinner.startAnimation(nil)
        branches.isEnabled = false; more.isEnabled = false
        footer.stringValue = title + "…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try work() }
            DispatchQueue.main.async {
                guard let self else { return }
                self.operationRunning = false; self.spinner.stopAnimation(nil)
                self.branches.isEnabled = true; self.more.isEnabled = true
                switch result {
                case .success(let destination): self.open(destination.path, focusHead: true)
                case .failure(let error): self.refreshNow(); self.showError(error.localizedDescription)
                }
            }
        }
    }
    func checkoutWorktree(_ commit: Commit, repo: Repository, reference: String? = nil) {
        guard !operationRunning, repository?.path == repo.path else { return }
        let refs = repo.references.filter { $0.target == commit.id && !$0.symbolic }
        if let reference, let ref = refs.first(where: { $0.name == reference }) {
            if ref.name.hasPrefix("refs/remotes/") {
                navigateRepository(title: "Checking out " + ref.shortName, repo: repo) { try Git.checkoutRemote(ref.name, at: repo.path, expectedSignature: repo.signature) }
            } else if ref.isBranch { createAutomaticWorktree(start: commit.id, branch: ref.shortName) }
            else { createAutomaticWorktree(start: commit.id) }
            return
        }
        // A row can carry several refs. Prefer origin, then a stable lexical order, without a chooser.
        let remote = refs.filter { $0.name.hasPrefix("refs/remotes/") }.sorted { a, b in
            if a.shortName.hasPrefix("origin/") != b.shortName.hasPrefix("origin/") { return a.shortName.hasPrefix("origin/") }
            return a.name < b.name
        }.first
        if let remote {
            navigateRepository(title: "Checking out " + remote.shortName, repo: repo) { try Git.checkoutRemote(remote.name, at: repo.path, expectedSignature: repo.signature) }
        } else {
            let branch = refs.filter(\.isBranch).sorted { $0.name < $1.name }.first?.shortName
            createAutomaticWorktree(start: commit.id, branch: branch)
        }
    }
    func resetDialog(_ commit: Commit, repo: Repository) {
        let mode = NSPopUpButton()
        mode.addItems(withTitles: ["Soft — keep changes staged", "Mixed — keep changes, unstage files", "Hard — discard local changes"])
        mode.selectItem(at: 1)
        let alert = inputForm("Reset Current Branch", detail: "Move \(repo.branch) to \(commit.id.prefix(8)).\n\nSoft keeps changes staged. Mixed keeps file changes but unstages them. Hard discards tracked changes and may remove untracked files that obstruct target files.\n\nA backup branch saves the previous HEAD, not uncommitted changes.", controls: [mode])
        alert.alertStyle = .warning
        alert.beginSheetModal(for: window!) { [weak self] response in
            guard response == .alertSecondButtonReturn else { return }
            let modes = ["soft", "mixed", "hard"]
            guard modes.indices.contains(mode.indexOfSelectedItem) else { return }
            self?.execute(.reset(commit: commit.id, mode: modes[mode.indexOfSelectedItem]), repo: repo, title: "Reset Current Branch")
        }
    }
    func tagDialog(_ commit: Commit, repo: Repository) {
        let name = nameField("Tag name"), annotation = nameField("Annotation (optional)")
        let alert = inputForm("Add Tag", detail: "Tag commit \(commit.id.prefix(8)). An annotation creates an annotated tag; otherwise the tag is lightweight.", controls: [name, annotation])
        alert.beginSheetModal(for: window!) { [weak self] response in
            if response == .alertSecondButtonReturn { self?.execute(.addTag(name: name.stringValue, commit: commit.id, message: annotation.stringValue), repo: repo, title: "Add Tag") }
        }
        alert.window.makeFirstResponder(name)
    }
    func renameBranchDialog(_ old: String, repo: Repository) {
        let name = nameField("New branch name", value: old)
        let alert = inputForm("Rename Branch", detail: "Rename local branch \(old).", controls: [name])
        alert.beginSheetModal(for: window!) { [weak self] response in
            if response == .alertSecondButtonReturn { self?.execute(.renameBranch(old: old, new: name.stringValue), repo: repo, title: "Rename Branch") }
        }
    }
    func mainlineDialog(_ commit: Commit, repo: Repository, revert: Bool) {
        let title = revert ? "Revert Commit" : "Cherry-pick Commit"
        let detail = revert ? "Create a new commit on \(repo.branch) that reverses \(commit.id.prefix(8))." : "Apply \(commit.id.prefix(8)) as a new commit on \(repo.branch)."
        if commit.parents.count < 2 {
            confirmAction(title, detail: detail + " A clean working tree is required.", repo: repo, action: revert ? .revert(commit: commit.id, mainline: nil) : .cherryPick(commit: commit.id, mainline: nil)); return
        }
        let parents = NSPopUpButton()
        parents.addItems(withTitles: commit.parents.enumerated().map { "Parent \($0.offset+1): \($0.element.prefix(8))" })
        let alert = inputForm(title, detail: detail + "\n\nThis is a merge commit. Select the mainline parent whose changes Git should use as the baseline.", controls: [parents])
        alert.beginSheetModal(for: window!) { [weak self] response in
            if response == .alertSecondButtonReturn {
                let parent = parents.indexOfSelectedItem+1
                self?.execute(revert ? .revert(commit: commit.id, mainline: parent) : .cherryPick(commit: commit.id, mainline: parent), repo: repo, title: title)
            }
        }
    }
    func mergeDialog(_ commit: Commit, repo: Repository) {
        let mode = NSPopUpButton(); mode.addItems(withTitles: ["Fast-forward when possible", "Always create a merge commit", "Squash changes (stage without committing)"])
        let alert = inputForm("Merge Commit", detail: "Merge \(commit.id.prefix(8)) into \(repo.branch). A clean working tree is required.", controls: [mode])
        alert.beginSheetModal(for: window!) { [weak self] response in
            if response == .alertSecondButtonReturn { self?.execute(.merge(commit: commit.id, noFastForward: mode.indexOfSelectedItem == 1, squash: mode.indexOfSelectedItem == 2), repo: repo, title: "Merge Commit") }
        }
    }
}
