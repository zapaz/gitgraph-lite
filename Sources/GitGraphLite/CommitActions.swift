import AppKit
import GitGraphCore

final class CommitTableView: NSTableView {
    var menuProvider: ((Int, HistoryMenuTarget) -> NSMenu?)?
    func handleFoldClick(_ event: NSEvent) -> Bool {
        let index = row(at: convert(event.locationInWindow, from: nil))
        if index >= 0 {
            for name in ["graph", "subject"] {
                guard let column = tableColumns.firstIndex(where: { $0.identifier.rawValue == name }), let cell = view(atColumn: column, row: index, makeIfNecessary: false) else { continue }
                let point = cell.convert(event.locationInWindow, from: nil)
                if let graph = cell as? GraphCell, graph.handleFoldClick(at: point) { return true }
                if let commit = cell as? CommitCell, commit.handleFoldClick(at: point) { return true }
            }
        }
        return false
    }
    override func mouseDown(with event: NSEvent) {
        if !handleFoldClick(event) { super.mouseDown(with: event) }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let index = row(at: convert(event.locationInWindow, from: nil))
        guard index >= 0 else { return nil }
        var target = HistoryMenuTarget.commit
        if let column = tableColumns.firstIndex(where: { $0.identifier.rawValue == "subject" }), let cell = view(atColumn: column, row: index, makeIfNecessary: false) as? CommitCell {
            target = cell.contextTarget(at: cell.convert(event.locationInWindow, from: nil))
        }
        if !selectedRowIndexes.contains(index) { selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
        return menuProvider?(index, target)
    }
}

final class MenuCommand: NSObject {
    let id: CommitActionID
    let kind: ActionItemKind
    let usage: ActionUsage
    let handler: () -> Void
    init(id: CommitActionID, kind: ActionItemKind = .commit, usage: ActionUsage, handler: @escaping () -> Void) {
        self.id = id; self.kind = kind; self.usage = usage; self.handler = handler
    }
    @objc func invoke(_ sender: Any?) {
        guard (sender as? NSMenuItem)?.isEnabled != false else { return }
        usage.record(id, kind: kind)
        handler()
    }
}

extension Controller {
    func copyText(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }

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
    func openLocalWorkspace(_ branch: String, repo: Repository) {
        navigateRepository(title: "Opening " + branch, repo: repo) { try Git.openLocalBranch(branch, at: repo.path, expectedSignature: repo.signature) }
    }
    func openRemoteWorkspace(_ reference: String, repo: Repository) {
        navigateRepository(title: "Opening remote branch locally", repo: repo) { try Git.openRemoteBranch(reference, at: repo.path, expectedSignature: repo.signature) }
    }
    func createLocalBranchOnly(start: String = "HEAD", remote: String? = nil) {
        guard let repo = repository, !operationRunning else { return }
        operationRunning = true; branches.isEnabled = false; more.isEnabled = false; spinner.startAnimation(nil)
        footer.stringValue = "Creating local branch…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                if let remote { return try Git.createLocalBranchFromRemote(remote, at: repo.path, expectedSignature: repo.signature) }
                return try Git.createLocalBranch(at: repo.path, start: start, expectedSignature: repo.signature)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.operationRunning = false; self.branches.isEnabled = true; self.more.isEnabled = true; self.spinner.stopAnimation(nil)
                switch result {
                case .success: self.refreshNow()
                case .failure(let error): self.refreshNow(); self.showError(error.localizedDescription)
                }
            }
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
            if response == .alertSecondButtonReturn { self?.executeItemAction(.renameBranch(old: old, new: name.stringValue), repo: repo, title: "Rename Branch") }
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
