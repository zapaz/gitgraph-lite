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
    func copyPopup(_ label: String, _ value: String) {
        // The copied value is shown with its own copy button too, like every value in a popup.
        actionPopup(label + " copied") { [weak self] in
            self?.copyText(value); return ("", [.init(label: label, value: value)], "")
        }
    }
    /// Lite: one field, a lightweight tag. The commit is the one that was right-clicked.
    func tagDialog(_ commit: Commit, repo: Repository) {
        let name = nameField("Tag name")
        actionPopup("Add Tag", controls: [name], required: [name], confirm: "Add Tag", focus: name, running: "Adding tag", git: repo) {
            let tag = DispatchQueue.main.sync { name.stringValue.trimmingCharacters(in: .whitespaces) }
            let result = try Git.perform(.addTag(name: tag, commit: commit.id, message: ""), at: repo.path, expectedSignature: repo.signature)
            return ("Tag added.", [.init(label: "Tag", value: tag)], result.output)
        }
    }
    /// Lite: one field, prefilled with a short name taken from the commit subject.
    func createBranchDialog(_ commit: Commit, repo: Repository) {
        let taken = Set(repo.references.filter(\.isBranch).map(\.shortName))
        let name = nameField("Branch name", value: Git.shortBranchName(subject: commit.subject, commit: commit.id, taken: taken))
        actionPopup("Create Branch", controls: [name], required: [name], confirm: "Create Branch", focus: name, running: "Creating branch", git: repo) {
            let typed = DispatchQueue.main.sync { name.stringValue.trimmingCharacters(in: .whitespaces) }
            let branch = try Git.createLocalBranch(at: repo.path, start: commit.id, name: typed, expectedSignature: repo.signature)
            return ("Branch created.", [.init(label: "Branch", value: branch)], "")
        }
    }
    /// Lite: one required field, prefilled with the current name. Pins and the branch selection follow the rename.
    func renameBranchDialog(_ old: String, repo: Repository) {
        let name = nameField("New branch name", value: old)
        actionPopup("Rename Branch", controls: [name], required: [name], confirm: "Rename", focus: name, running: "Renaming", git: repo) {
            let new = DispatchQueue.main.sync { name.stringValue.trimmingCharacters(in: .whitespaces) }
            _ = try Git.performItem(.renameBranch(old: old, new: new), at: repo.path, expectedSignature: repo.signature)
            DispatchQueue.main.sync { [weak self] in
                guard let self else { return }
                if self.branchPins.remove(old) != nil || old == "main" || old == "master" { self.branchPins.insert(new); self.saveBranchPins() }
                if self.branchSelection?.remove(old) != nil { self.branchSelection?.insert(new) }
            }
            return ("Branch renamed.", [.init(label: "Branch", value: new)], "")
        }
    }
    func mainlineDialog(_ commit: Commit, repo: Repository, revert: Bool) {
        let title = revert ? "Revert" : "Cherry Pick"
        let target = repo.branch
        var controls: [NSView] = []
        let parents = NSPopUpButton()
        if commit.parents.count >= 2 {
            parents.addItems(withTitles: commit.parents.enumerated().map { "Mainline parent \($0.offset+1): \($0.element.prefix(8))" })
            controls = [parents]
        }
        // Lite: only where the commit lands. A merge commit also needs its mainline parent.
        let facts: [ActionPopup.Fact] = [.init(label: "Onto", value: target)]
        actionPopup(title, facts: facts, controls: controls, confirm: title, running: revert ? "Reverting" : "Cherry-picking", git: repo) {
            let mainline: Int? = controls.isEmpty ? nil : DispatchQueue.main.sync { parents.indexOfSelectedItem+1 }
            let result = try Git.perform(revert ? .revert(commit: commit.id, mainline: mainline) : .cherryPick(commit: commit.id, mainline: mainline), at: repo.path, expectedSignature: repo.signature)
            var done = facts
            if let backup = result.backup { done.append(.init(label: "Backup", value: backup)) }
            return (revert ? "Commit reverted." : "Commit applied.", done, result.output)
        }
    }
    /// Always a real merge commit (--no-ff), so the branch stays visible in the graph. No mode to choose.
    func mergeDialog(_ commit: Commit, repo: Repository) {
        let target = repo.branch
        let facts: [ActionPopup.Fact] = [.init(label: "Branch", value: commit.subject), .init(label: "Commit", value: commit.id), .init(label: "Into", value: target)]
        actionPopup("Merge", detail: "Create a merge commit on \(target), even when a fast-forward is possible. A clean working tree is required.", facts: facts, confirm: "Merge", running: "Merging", git: repo) {
            let result = try Git.perform(.merge(commit: commit.id, noFastForward: true, squash: false), at: repo.path, expectedSignature: repo.signature)
            return ("Merged into \(target).", facts, result.output)
        }
    }
}
