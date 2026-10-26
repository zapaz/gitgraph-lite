import AppKit
import GitGraphCore

final class CommitTableView: NSTableView {
    var menuProvider: ((Int) -> NSMenu?)?
    override func menu(for event: NSEvent) -> NSMenu? {
        let index = row(at: convert(event.locationInWindow, from: nil))
        guard index >= 0 else { return nil }
        if !selectedRowIndexes.contains(index) { selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
        return menuProvider?(index)
    }
}

private final class MenuCommand: NSObject {
    let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func invoke(_ sender: Any?) { handler() }
}

extension Controller {
    func commitMenu(at row: Int) -> NSMenu? {
        guard let commit = commit(at: row), let repo = repository else { return nil }
        let menu = NSMenu(); menu.autoenablesItems = false
        func add(_ title: String, to parent: NSMenu? = nil, enabled: Bool = true, _ handler: @escaping () -> Void) {
            let command = MenuCommand(handler)
            let item = NSMenuItem(title: title, action: #selector(MenuCommand.invoke(_:)), keyEquivalent: "")
            item.target = command; item.representedObject = command; item.isEnabled = enabled
            (parent ?? menu).addItem(item)
        }
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let sub = NSMenu(); sub.autoenablesItems = false; item.submenu = sub; menu.addItem(item); return sub
        }
        let title = NSMenuItem(title: String(commit.id.prefix(8)) + " · " + String(commit.subject.prefix(65)), action: nil, keyEquivalent: "")
        title.isEnabled = false; menu.addItem(title)
        add("Copy Commit Hash") { [weak self] in self?.copyText(commit.id) }
        add("Copy Commit Message") { [weak self] in
            self?.readFromRepository(repo.path) { try Git.message(at: repo.path, commit: commit.id) } completion: { text in self?.copyText(text) }
        }
        menu.addItem(.separator())
        add("Compare with HEAD") { [weak self] in
            self?.readFromRepository(repo.path) { try Git.string(["rev-parse", "HEAD"], at: repo.path) } completion: { head in self?.showDetails(for: commit, base: head) }
        }
        add("Select for Comparison") { [weak self] in self?.comparisonAnchor = commit; self?.footer.stringValue = "Right-click another commit and choose Compare with \(commit.id.prefix(8))." }
        if let anchor = comparisonAnchor, anchor.id != commit.id {
            add("Compare with \(anchor.id.prefix(8))") { [weak self] in self?.showDetails(for: commit, base: anchor.id) }
        }
        let selected = table.selectedRowIndexes.compactMap { self.commit(at: $0) }
        if selected.count == 2 {
            add("Compare Selected Commits") { [weak self] in self?.showDetails(for: selected[0], base: selected[1].id) }
        }
        menu.addItem(.separator())
        let canWrite = !loading && !operationRunning && repo.pendingOperation == nil
        let current = repo.branch
        add("Create Worktree Here…", enabled: !loading && !operationRunning) { [weak self] in
            self?.manageWorktrees(start: commit.id)
        }
        add("Add Tag…", enabled: canWrite) { [weak self] in self?.tagDialog(commit, repo: repo) }
        menu.addItem(.separator())
        add("Cherry-pick Commit…", enabled: canWrite) { [weak self] in self?.mainlineDialog(commit, repo: repo, revert: false) }
        add("Revert Commit…", enabled: canWrite) { [weak self] in self?.mainlineDialog(commit, repo: repo, revert: true) }
        add("Merge into Current Branch…", enabled: canWrite) { [weak self] in self?.mergeDialog(commit, repo: repo) }
        add("Rebase Current Branch onto Commit…", enabled: canWrite) { [weak self] in
            self?.confirmAction("Rebase Current Branch", detail: "Rebase \(current) onto \(commit.id.prefix(8)). This rewrites commit hashes and preserves merge structure. A backup branch will save the previous HEAD. A clean working tree is required.", repo: repo, action: .rebase(commit.id), destructive: true)
        }
        let resets = submenu("Reset Current Branch to Commit")
        for (mode, explanation) in [("soft", "Keep all file changes staged."), ("mixed", "Keep file changes in the working tree, but unstage them."), ("hard", "Discard tracked local changes. Untracked files that obstruct target files may also be removed.")] {
            add("\(mode.capitalized)…", to: resets, enabled: canWrite) { [weak self] in
                self?.confirmAction("\(mode.capitalized) Reset", detail: "Move \(current) to \(commit.id.prefix(8)). \(explanation)\n\nA backup branch will save the previous HEAD, but does not save uncommitted changes.", repo: repo, action: .reset(commit: commit.id, mode: mode), destructive: true)
            }
        }
        add("Drop Commit…", enabled: canWrite && commit.parents.count == 1) { [weak self] in
            self?.confirmAction("Drop Commit", detail: "Remove \(commit.id.prefix(8)) from the current branch's history and replay its descendants. This rewrites commit hashes. The commit must be an ancestor of \(current). A backup branch will save the previous HEAD.", repo: repo, action: .drop(commit.id), destructive: true)
        }
        for ref in repo.references where ref.target == commit.id && !ref.symbolic {
            guard ref.isBranch || ref.isTag else { continue }
            let sub = submenu((ref.isBranch ? "Branch: " : "Tag: ") + ref.shortName)
            if ref.isBranch {
                let occupied = repo.worktrees.first { $0.branch == ref.name }
                if let occupied {
                    let active = Git.samePath(occupied.path, repo.path)
                    add(active ? "Current Worktree: \(occupied.name)" : "Open Worktree: \(occupied.name)", to: sub, enabled: occupied.exists && !operationRunning && !active) { [weak self] in self?.open(occupied.path) }
                } else {
                    add("Create Worktree on This Branch…", to: sub, enabled: !loading && !operationRunning) { [weak self] in self?.manageWorktrees(start: commit.id, branch: ref.shortName) }
                }
                add("Copy Branch Name", to: sub) { [weak self] in self?.copyText(ref.shortName) }
                add("Rename Branch…", to: sub, enabled: canWrite && occupied == nil) { [weak self] in self?.renameBranchDialog(ref.shortName, repo: repo) }
                add("Delete Branch…", to: sub, enabled: canWrite && ref.shortName != current && occupied == nil) { [weak self] in
                    self?.confirmAction("Delete Branch", detail: "Delete local branch \(ref.shortName). Git will refuse if it contains unmerged work. The branch will not be deleted from any remote.", repo: repo, action: .deleteBranch(ref.shortName), destructive: true)
                }
            } else {
                add("Copy Tag Name", to: sub) { [weak self] in self?.copyText(ref.shortName) }
                add("Delete Tag…", to: sub, enabled: canWrite) { [weak self] in
                    self?.confirmAction("Delete Tag", detail: "Delete local tag \(ref.shortName). The tag will not be deleted from any remote.", repo: repo, action: .deleteTag(ref.shortName), destructive: true)
                }
            }
        }
        if let operation = repo.pendingOperation {
            menu.addItem(.separator())
            add("Continue \(operation.capitalized)…", enabled: !operationRunning) { [weak self] in
                self?.confirmAction("Continue \(operation.capitalized)", detail: "Resolve conflicts in your editor and stage the resolved files first, then continue the pending \(operation).", repo: repo, action: .continueOperation(operation))
            }
            add("Abort \(operation.capitalized)…", enabled: !operationRunning) { [weak self] in
                self?.confirmAction("Abort \(operation.capitalized)", detail: "Abort the pending \(operation) and return to its previous state. Conflict-resolution work may be discarded.", repo: repo, action: .abortOperation(operation), destructive: true)
            }
        }
        return menu
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
