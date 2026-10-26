import AppKit
import GitGraphCore

extension Controller {
    func updateWorktreePicker(_ repo: Repository) {
        worktreePicker.removeAllItems()
        worktreePicker.addItems(withTitles: repo.worktrees.map { "\($0.name)  ·  \($0.branchLabel)" })
        for (i, tree) in repo.worktrees.enumerated() {
            worktreePicker.item(at: i)?.isEnabled = tree.exists && !tree.isBare
            worktreePicker.item(at: i)?.toolTip = tree.path + "\n" + tree.stateLabel
            if Git.samePath(tree.path, repo.path) {
                worktreePicker.selectItem(at: i); worktreeState.stringValue = tree.stateLabel
            }
        }
        worktreePicker.isEnabled = !operationRunning
    }
    @objc func worktreeChanged() {
        guard !operationRunning, let repo = repository, repo.worktrees.indices.contains(worktreePicker.indexOfSelectedItem) else { return }
        let tree = repo.worktrees[worktreePicker.indexOfSelectedItem]
        guard tree.exists && !tree.isBare else { return }
        worktreeManager?.close(); open(tree.path)
    }
    @objc func showWorktreeManager() { manageWorktrees(start: nil) }
    func manageWorktrees(start: String?) {
        guard !operationRunning, let repo = repository else { return }
        worktreeManager?.close()
        let manager = WorktreeManager(owner: self, path: repo.path)
        worktreeManager = manager; manager.showWindow(nil); manager.window?.makeKeyAndOrderFront(nil)
        if let start { manager.createWhenLoaded = start }
        manager.reload()
    }
}

final class WorktreeManager: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    weak var browser: Controller?
    let repoPath: String
    let table = NSTableView()
    let summary = NSTextField(labelWithString: "Loading worktrees…")
    let detail = NSTextField(labelWithString: "")
    var trees: [GitWorktree] = []
    var branches: [String] = []
    var busy = false
    var createWhenLoaded: String?
    let openButton = NSButton(title: "Open", target: nil, action: nil)
    let moveButton = NSButton(title: "Move…", target: nil, action: nil)
    let lockButton = NSButton(title: "Lock", target: nil, action: nil)
    let removeButton = NSButton(title: "Remove…", target: nil, action: nil)
    let createButton = NSButton(title: "Create Worktree…", target: nil, action: nil)
    let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)

    init(owner: Controller, path: String) {
        self.browser = owner; repoPath = path
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 450), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Worktrees — " + URL(fileURLWithPath: path).lastPathComponent
        window.minSize = NSSize(width: 850, height: 340); window.isReleasedWhenClosed = false
        super.init(window: window); build(); window.center()
    }
    required init?(coder: NSCoder) { fatalError() }
    func build() {
        let root = window!.contentView!
        summary.font = .systemFont(ofSize: 16, weight: .semibold)
        detail.font = .systemFont(ofSize: 11); detail.textColor = .secondaryLabelColor; detail.lineBreakMode = .byTruncatingMiddle
        table.delegate = self; table.dataSource = self; table.rowHeight = 36
        table.usesAlternatingRowBackgroundColors = true; table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.doubleAction = #selector(openSelected); table.target = self
        for (id, title, width) in [("name", "WORKTREE", 170.0), ("branch", "BRANCH / HEAD", 220.0), ("state", "STATE", 180.0), ("path", "LOCATION", 420.0)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); c.title = title; c.width = width; c.minWidth = 90; table.addTableColumn(c)
        }
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        let top = NSStackView(views: [summary, refreshButton]); top.distribution = .fill; top.spacing = 20
        summary.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let reveal = NSButton(title: "Show in Finder", target: self, action: #selector(revealSelected))
        let buttons = NSStackView(views: [createButton, openButton, reveal, moveButton, lockButton, removeButton]); buttons.spacing = 8
        for button in [createButton, openButton, reveal, moveButton, lockButton, removeButton, refreshButton] { button.bezelStyle = .rounded }
        createButton.target = self; createButton.action = #selector(createSelected)
        openButton.target = self; openButton.action = #selector(openSelected)
        moveButton.target = self; moveButton.action = #selector(moveSelected)
        lockButton.target = self; lockButton.action = #selector(lockSelected)
        removeButton.target = self; removeButton.action = #selector(removeSelected)
        refreshButton.target = self; refreshButton.action = #selector(reload)
        for view in [top, scroll, detail, buttons] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        NSLayoutConstraint.activate([
            top.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18), top.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18), top.topAnchor.constraint(equalTo: root.topAnchor, constant: 16), top.heightAnchor.constraint(equalToConstant: 28),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor), scroll.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 14),
            detail.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18), detail.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18), detail.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 12), detail.heightAnchor.constraint(equalToConstant: 18),
            buttons.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18), buttons.topAnchor.constraint(equalTo: detail.bottomAnchor, constant: 10), buttons.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16), buttons.heightAnchor.constraint(equalToConstant: 30)
        ])
        updateButtons()
    }
    var selected: GitWorktree? { trees.indices.contains(table.selectedRow) ? trees[table.selectedRow] : nil }
    @objc func reload() {
        guard !busy else { return }; busy = true; updateButtons()
        let previous = selected?.path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = Result { (try Git.worktrees(at: self.repoPath), try Git.references(at: self.repoPath).filter(\.isBranch).map(\.shortName)) }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let (trees, branches)):
                    self.trees = trees; self.branches = branches; self.table.reloadData()
                    let row = previous.flatMap { old in trees.firstIndex { Git.samePath($0.path, old) } } ?? trees.firstIndex { Git.samePath($0.path, self.browser?.repository?.path ?? self.repoPath) } ?? 0
                    if trees.indices.contains(row) { self.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
                    self.summary.stringValue = "\(trees.count) worktrees"
                    self.updateButtons()
                    if let start = self.createWhenLoaded { self.createWhenLoaded = nil; self.create(start: start) }
                case .failure(let error): self.presentError(error.localizedDescription)
                }
            }
        }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { trees.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier else { return nil }
        let tree = trees[row]
        let label = (tableView.makeView(withIdentifier: id, owner: self) as? NSTextField) ?? NSTextField(labelWithString: "")
        label.identifier = id; label.font = .systemFont(ofSize: 11); label.lineBreakMode = .byTruncatingMiddle
        switch id.rawValue {
        case "name": label.stringValue = (Git.samePath(tree.path, browser?.repository?.path ?? repoPath) ? "● " : "") + tree.name
        case "branch": label.stringValue = tree.branchLabel
        case "state": label.stringValue = tree.stateLabel
        default: label.stringValue = tree.path
        }
        label.toolTip = tree.path + "\n" + tree.stateLabel + (tree.lockReason.map { "\n" + $0 } ?? "")
        label.textColor = !tree.exists ? .systemRed : id.rawValue == "state" && tree.changedFiles == 0 ? .systemGreen : .labelColor
        return label
    }
    func tableViewSelectionDidChange(_ notification: Notification) { updateButtons() }
    func updateButtons() {
        let tree = selected
        let active = tree.map { Git.samePath($0.path, browser?.repository?.path ?? repoPath) } ?? false
        let editable = !busy && browser?.operationRunning != true
        openButton.isEnabled = editable && tree?.exists == true && tree?.isBare == false
        moveButton.isEnabled = editable && tree?.isMain == false && tree?.isLocked == false && tree?.exists == true && !active
        removeButton.isEnabled = moveButton.isEnabled
        lockButton.isEnabled = editable && tree?.isMain == false
        lockButton.title = tree?.isLocked == true ? "Unlock" : "Lock…"
        createButton.isEnabled = editable; refreshButton.isEnabled = !busy
        detail.stringValue = tree.map { $0.path + ($0.lockReason.flatMap { $0.isEmpty ? nil : " — " + $0 } ?? "") } ?? "Select a worktree. Removing a worktree keeps its branch."
    }
    @objc func openSelected() {
        guard let tree = selected, tree.exists, !tree.isBare, !busy else { return }
        browser?.open(tree.path); close()
    }
    @objc func revealSelected() { if let tree = selected, tree.exists { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: tree.path) } }
    @objc func createSelected() { create(start: "HEAD") }
    func chooseDestination(_ title: String, suggestion: String, completion: @escaping (String) -> Void) {
        let panel = NSSavePanel(); panel.title = title; panel.prompt = "Choose Location"; panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestion
        panel.directoryURL = URL(fileURLWithPath: repoPath).deletingLastPathComponent()
        panel.beginSheetModal(for: window!) { response in
            if response == .OK, let path = panel.url?.path { DispatchQueue.main.async { completion(path) } }
        }
    }
    func create(start: String) {
        guard !busy else { return }
        chooseDestination("New worktree folder", suggestion: URL(fileURLWithPath: repoPath).lastPathComponent + "-worktree") { [weak self] path in
            guard let self else { return }
            let mode = NSPopUpButton(); mode.addItems(withTitles: ["Create a new branch", "Use an existing local branch", "Detached HEAD"])
            let name = NSTextField(string: ""); name.placeholderString = "New branch name (for new-branch mode)"
            let existing = NSPopUpButton()
            let available = self.branches.filter { branch in !self.trees.contains { $0.branch == "refs/heads/" + branch } }
            existing.addItems(withTitles: available.isEmpty ? ["No unused local branches"] : available)
            mode.item(at: 1)?.isEnabled = !available.isEmpty
            let revision = NSTextField(string: start); revision.placeholderString = "Starting commit or ref (new branch / detached)"
            let open = NSButton(checkboxWithTitle: "Open the new worktree", target: nil, action: nil); open.state = .on
            let alert = self.form("Create Worktree", detail: "Location: \(path)\nChoose a mode. The branch-name field applies to new branches; the branch menu applies to existing branches.", controls: [mode, name, existing, revision, open])
            alert.beginSheetModal(for: self.window!) { response in
                guard response == .alertSecondButtonReturn else { return }
                let source: WorktreeSource
                switch mode.indexOfSelectedItem {
                case 1: guard available.indices.contains(existing.indexOfSelectedItem) else { return }; source = .existingBranch(available[existing.indexOfSelectedItem])
                case 2: source = .detached(revision.stringValue)
                default: source = .newBranch(name: name.stringValue, start: revision.stringValue)
                }
                self.run(.add(path: path, source: source), title: "Create Worktree", openAfter: open.state == .on ? path : nil)
            }
        }
    }
    @objc func removeSelected() {
        guard let tree = selected else { return }
        let preserved = tree.branch == nil ? "Its detached HEAD will be saved to a backup branch." : "Its branch is kept."
        confirm("Remove Worktree", detail: "Remove the folder \(tree.path).\n\n\(preserved) Modified, untracked, locked or active worktrees will not be removed. Git's force option is never used.") { [weak self] in self?.run(.remove(tree.path), title: "Remove Worktree") }
    }
    @objc func moveSelected() {
        guard let tree = selected else { return }
        chooseDestination("Move worktree", suggestion: tree.name + "-moved") { [weak self] path in
            self?.confirm("Move Worktree", detail: "Move \(tree.path) to \(path) and update Git's worktree registration. A clean, unlocked worktree is required.") { [weak self] in self?.run(.move(path: tree.path, destination: path), title: "Move Worktree") }
        }
    }
    @objc func lockSelected() {
        guard let tree = selected else { return }
        if tree.isLocked {
            confirm("Unlock Worktree", detail: "Unlock \(tree.path), allowing it to be moved, removed or pruned.") { [weak self] in self?.run(.unlock(tree.path), title: "Unlock Worktree") }
        } else {
            let reason = NSTextField(string: ""); reason.placeholderString = "Lock reason (optional)"
            let alert = form("Lock Worktree", detail: "Protect \(tree.path) from removal, movement and pruning.", controls: [reason])
            alert.beginSheetModal(for: window!) { [weak self] response in
                if response == .alertSecondButtonReturn { self?.run(.lock(path: tree.path, reason: reason.stringValue), title: "Lock Worktree") }
            }
        }
    }
    func form(_ title: String, detail: String, controls: [NSView]) -> NSAlert {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: title)
        let stack = NSStackView(views: controls); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.frame = NSRect(x: 0, y: 0, width: 440, height: CGFloat(controls.count)*34)
        for control in controls { control.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        alert.accessoryView = stack; return alert
    }
    func confirm(_ title: String, detail: String, completion: @escaping () -> Void) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail; alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: title)
        alert.beginSheetModal(for: window!) { response in if response == .alertSecondButtonReturn { completion() } }
    }
    func run(_ action: WorktreeAction, title: String, openAfter: String? = nil) {
        guard !busy, browser?.operationRunning != true else { return }
        busy = true; browser?.operationRunning = true; updateButtons(); summary.stringValue = title + "…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = Result { try Git.performWorktree(action, at: self.repoPath) }
            DispatchQueue.main.async {
                self.busy = false; self.browser?.operationRunning = false
                self.browser?.refreshNow(); self.reload()
                switch result {
                case .success(let output):
                    if let openAfter { self.browser?.open(openAfter); self.close() }
                    else if !output.isEmpty {
                        let alert = NSAlert(); alert.messageText = title + " completed"; alert.informativeText = String(output.prefix(2500)); alert.beginSheetModal(for: self.window!)
                    }
                case .failure(let error): self.presentError(error.localizedDescription)
                }
            }
        }
    }
    func presentError(_ text: String) {
        updateButtons(); let alert = NSAlert(); alert.messageText = "Worktree action could not finish"; alert.informativeText = text; alert.alertStyle = .warning
        alert.beginSheetModal(for: window!)
    }
}
