import AppKit
import GitGraphCore

final class Controller: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    let table = CommitTableView()
    let fileTable = NSTableView()
    let diffViewer = DiffViewer()
    let message = NSTextView()
    let repoTitle = NSTextField(labelWithString: "GitGraph Lite")
    let repoSubtitle = NSTextField(labelWithString: "A clear view of your history")
    let footer = NSTextField(labelWithString: "Open a local Git repository to begin.")
    let detailTitle = NSTextField(labelWithString: "Select a commit to inspect its changes")
    let fileTitle = NSTextField(labelWithString: "FILES")
    let search = NSSearchField()
    let branches = NSButton(title: "All branches ▾", target: nil, action: nil)
    let branchPopover = NSPopover()
    var branchPins = Set<String>()
    var branchSelection: Set<String>?
    let groupingToggle = NSButton(checkboxWithTitle: "Plié", target: nil, action: nil)
    var groupsFolded = UserDefaults.standard.object(forKey: "groupCommits") as? Bool ?? true
    var groupOverrides = Set<String>()
    var historyGroups: [HistoryGroup] = []
    var groupHeaders: [Int: HistoryGroup] = [:]
    let spinner = NSProgressIndicator()
    let more = NSButton(title: "Load more", target: nil, action: nil)
    var repository: Repository?
    var commits: [Commit] = []
    var graph: [GraphRow] = []
    var visibleGraph: [GraphRow] = []
    var labelsByCommit: [String: [ReferenceLabel]] = [:]
    var activeHead: String?
    var visibleIndices: [Int] = []
    var files: [ChangedFile] = []
    var fileRows: [FileTreeRow] = []
    var collapsedDirectories = Set<String>()
    var fileTreeMode = UserDefaults.standard.object(forKey: "fileTreeMode") as? Bool ?? true
    let fileMode = NSSegmentedControl(labels: ["Tree", "Paths"], trackingMode: .selectOne, target: nil, action: nil)
    var limit = 500
    var target: String?
    var base: String?
    var loadID = UUID(), detailID = UUID(), patchID = UUID()
    var loading = false, checking = false, rebuilding = false
    var operationRunning = false
    var comparisonAnchor: Commit?
    var worktreeManager: WorktreeManager?
    var timer: Timer?
    let dateFormatter: DateFormatter = { let f = DateFormatter(); f.locale = .autoupdatingCurrent; f.timeZone = .autoupdatingCurrent; f.dateFormat = "d MMM yyyy HH:mm"; return f }()

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1260, height: 840), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "GitGraph Lite"; window.minSize = NSSize(width: 900, height: 600)
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildUI(); window.center(); window.setFrameAutosaveName("GitGraphLite.main")
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in self?.checkForChanges() }
    }
    required init?(coder: NSCoder) { fatalError() }

    func buildUI() {
        guard let root = window?.contentView else { return }
        let outer = NSStackView(); outer.orientation = .vertical; outer.spacing = 0; outer.alignment = .leading; outer.distribution = .fill
        outer.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(outer)
        NSLayoutConstraint.activate([outer.leadingAnchor.constraint(equalTo: root.leadingAnchor), outer.trailingAnchor.constraint(equalTo: root.trailingAnchor), outer.topAnchor.constraint(equalTo: root.topAnchor), outer.bottomAnchor.constraint(equalTo: root.bottomAnchor)])

        let appIcon = Bundle.main.path(forResource: "AppIcon", ofType: "icns").flatMap { NSImage(contentsOfFile: $0) }
        let logo = NSImageView(image: appIcon ?? NSImage(systemSymbolName: "point.3.connected.trianglepath.dotted", accessibilityDescription: "GitGraph Lite")!)
        logo.contentTintColor = .systemTeal; logo.imageScaling = .scaleProportionallyUpOrDown
        logo.widthAnchor.constraint(equalToConstant: 24).isActive = true
        logo.heightAnchor.constraint(equalToConstant: 24).isActive = true
        repoTitle.font = .systemFont(ofSize: 15, weight: .semibold); repoTitle.lineBreakMode = .byTruncatingMiddle
        repoTitle.widthAnchor.constraint(lessThanOrEqualToConstant: 160).isActive = true
        repoTitle.setContentCompressionResistancePriority(.init(500), for: .horizontal)
        repoSubtitle.font = .systemFont(ofSize: 11); repoSubtitle.textColor = .secondaryLabelColor
        repoSubtitle.lineBreakMode = .byTruncatingMiddle
        repoSubtitle.widthAnchor.constraint(lessThanOrEqualToConstant: 190).isActive = true
        repoSubtitle.setContentCompressionResistancePriority(.init(250), for: .horizontal)
        let open = NSButton(title: "Open…", target: self, action: #selector(openRepository)); open.bezelStyle = .rounded; open.toolTip = "Open Repository (⌘O)"
        let refresh = NSButton(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")!, target: self, action: #selector(refreshNow)); refresh.bezelStyle = .rounded; refresh.toolTip = "Refresh (⌘R)"
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        spinner.widthAnchor.constraint(equalToConstant: 16).isActive = true
        spinner.heightAnchor.constraint(equalToConstant: 16).isActive = true
        branches.bezelStyle = .rounded; branches.target = self; branches.action = #selector(showBranchPicker)
        branches.toolTip = "Filter the commit history. Open or create worktrees from the branch list."
        branches.widthAnchor.constraint(equalToConstant: 210).isActive = true
        search.placeholderString = "Search commits, authors or hashes"; search.delegate = self
        search.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        search.setContentHuggingPriority(.init(1), for: .horizontal)
        groupingToggle.target = self; groupingToggle.action = #selector(groupingChanged(_:))
        updateGroupingToggle()
        groupingToggle.toolTip = "Cocher pour tout plier ; décocher pour tout déplier. Chaque groupe reste ouvrable séparément."
        let header = NSStackView(views: [logo, repoTitle, repoSubtitle, branches, groupingToggle, search, spinner, refresh, open])
        header.orientation = .horizontal; header.alignment = .centerY; header.distribution = .fill; header.spacing = 8
        header.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        header.heightAnchor.constraint(equalToConstant: 44).isActive = true
        outer.addArrangedSubview(header)
        outer.addArrangedSubview(separator())

        table.delegate = self; table.dataSource = self
        table.menuProvider = { [weak self] row, reference in self?.commitMenu(at: row, reference: reference) }
        table.toolTip = "⌘-click two commits to compare"
        table.style = .plain
        table.rowHeight = 24; table.intercellSpacing = NSSize(width: 0, height: 0)
        table.allowsMultipleSelection = true; table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        for (id, title, width) in [("graph", "Graph", 96.0), ("subject", "Description", 600.0), ("date", "Date", 142.0), ("author", "Author", 90.0), ("hash", "Commit", 100.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); column.title = title; column.width = width
            column.minWidth = id == "subject" ? 180 : 55
            column.resizingMask = id == "subject" ? [.autoresizingMask, .userResizingMask] : [.userResizingMask]
            table.addTableColumn(column)
        }
        let graphScroll = NSScrollView(); graphScroll.hasVerticalScroller = true; graphScroll.hasHorizontalScroller = true; graphScroll.documentView = table

        let details = NSStackView(); details.orientation = .vertical; details.spacing = 0; details.alignment = .leading; details.distribution = .fill
        detailTitle.font = .systemFont(ofSize: 12, weight: .semibold); detailTitle.lineBreakMode = .byTruncatingTail
        let detailHeader = NSStackView(views: [detailTitle]); detailHeader.edgeInsets = NSEdgeInsets(top: 10, left: 20, bottom: 7, right: 20)
        detailHeader.heightAnchor.constraint(equalToConstant: 32).isActive = true
        details.addArrangedSubview(detailHeader)
        message.isEditable = false; message.isSelectable = true; message.drawsBackground = false; message.font = .systemFont(ofSize: 11)
        message.frame = NSRect(x: 0, y: 0, width: 1000, height: 55)
        message.isVerticallyResizable = true; message.autoresizingMask = [.width]
        message.textContainer?.widthTracksTextView = true
        message.textContainerInset = NSSize(width: 15, height: 4)
        let messageScroll = NSScrollView(); messageScroll.hasVerticalScroller = true; messageScroll.documentView = message
        messageScroll.heightAnchor.constraint(equalToConstant: 55).isActive = true
        details.addArrangedSubview(messageScroll); details.addArrangedSubview(separator())

        let bottom = NSSplitView(); bottom.isVertical = true; bottom.dividerStyle = .thin
        let filePane = NSStackView(); filePane.orientation = .vertical; filePane.alignment = .leading; filePane.spacing = 0; filePane.distribution = .fill
        fileTitle.font = .systemFont(ofSize: 10, weight: .semibold); fileTitle.textColor = .secondaryLabelColor
        fileMode.selectedSegment = fileTreeMode ? 0 : 1; fileMode.target = self; fileMode.action = #selector(fileModeChanged); fileMode.controlSize = .small
        let fileHeader = NSStackView(views: [fileTitle, fileMode]); fileHeader.spacing = 12; fileHeader.edgeInsets = NSEdgeInsets(top: 9, left: 12, bottom: 9, right: 12)
        fileHeader.heightAnchor.constraint(equalToConstant: 32).isActive = true
        filePane.addArrangedSubview(fileHeader)
        fileTable.delegate = self; fileTable.dataSource = self; fileTable.rowHeight = 27; fileTable.headerView = nil
        let fileCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file")); fileCol.width = 260; fileTable.addTableColumn(fileCol)
        let fileScroll = NSScrollView(); fileScroll.hasVerticalScroller = true; fileScroll.documentView = fileTable
        filePane.addArrangedSubview(fileScroll)
        filePane.widthAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true
        bottom.addArrangedSubview(filePane)
        bottom.addArrangedSubview(diffViewer)
        details.addArrangedSubview(bottom)

        let split = NSSplitView(); split.isVertical = false; split.dividerStyle = .thin
        split.addArrangedSubview(graphScroll); split.addArrangedSubview(details)
        graphScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
        details.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        outer.addArrangedSubview(split)
        outer.addArrangedSubview(separator())
        footer.font = .systemFont(ofSize: 11); footer.textColor = .secondaryLabelColor
        footer.lineBreakMode = .byTruncatingMiddle
        let readOnly = NSTextField(labelWithString: "LOCAL GIT"); readOnly.font = .systemFont(ofSize: 9, weight: .semibold); readOnly.textColor = .systemTeal
        more.target = self; more.action = #selector(loadMore); more.bezelStyle = .rounded; more.isHidden = true
        let foot = NSStackView(views: [footer, more, readOnly]); foot.edgeInsets = NSEdgeInsets(top: 7, left: 20, bottom: 7, right: 20); foot.spacing = 16
        foot.heightAnchor.constraint(equalToConstant: 36).isActive = true
        footer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        outer.addArrangedSubview(foot)
        for child in outer.arrangedSubviews { child.widthAnchor.constraint(equalTo: outer.widthAnchor).isActive = true }
        for child in details.arrangedSubviews { child.widthAnchor.constraint(equalTo: details.widthAnchor).isActive = true }
        for child in filePane.arrangedSubviews { child.widthAnchor.constraint(equalTo: filePane.widthAnchor).isActive = true }
        split.setContentHuggingPriority(.init(1), for: .vertical)
        bottom.setContentHuggingPriority(.init(1), for: .vertical)
        root.layoutSubtreeIfNeeded(); split.setPosition(350, ofDividerAt: 0); bottom.setPosition(290, ofDividerAt: 0)
        DispatchQueue.main.async {
            root.layoutSubtreeIfNeeded()
            split.setPosition(split.bounds.height * 0.48, ofDividerAt: 0)
            bottom.setPosition(280, ofDividerAt: 0)
        }
        setDiff("Open a repository, then select a commit and a file.\nRight-click a commit for Git actions.")
    }

    func separator() -> NSView {
        let line = NSBox(); line.boxType = .separator; line.heightAnchor.constraint(equalToConstant: 1).isActive = true; return line
    }

    @objc func openRepository() {
        guard !operationRunning else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.prompt = "Open Repository"
        panel.beginSheetModal(for: window!) { [weak self] response in
            if response == .OK, let path = panel.url?.path { self?.open(path) }
        }
    }

    func open(_ path: String, focusHead: Bool = false) {
        guard !operationRunning else { return }
        worktreeManager?.close()
        comparisonAnchor = nil
        limit = 500; branchSelection = nil; branchPopover.close(); search.stringValue = ""
        refresh(path: path, switching: true, focusHead: focusHead)
    }
    @objc func refreshNow() { guard !operationRunning else { return }; if let path = repository?.path { refresh(path: path) } else { openRepository() } }
    @objc func loadMore() { limit += 500; refreshNow() }
    func refresh(path: String, switching: Bool = false, focusHead: Bool = false) {
        let request = UUID(); loadID = request; loading = true; spinner.startAnimation(nil)
        let selection = branchSelection, pins = branchPins, count = limit
        footer.stringValue = "Loading history…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try Git.load(at: path, branchNames: selection, pins: pins, limit: count) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.loadID == request else { return }
                self.loading = false; self.spinner.stopAnimation(nil)
                switch result {
                case .success(let repo):
                    let selected = switching ? [] : self.table.selectedRowIndexes.compactMap { self.commit(at: $0)?.id }
                    self.repository = repo; self.commits = repo.commits; self.graph = GraphLayout.make(repo.commits)
                    self.labelsByCommit = Dictionary(grouping: repo.references, by: \.target).mapValues { ReferenceLabel.make($0, currentBranch: repo.branch) }
                    self.activeHead = repo.worktrees.first { Git.samePath($0.path, repo.path) }?.head
                    if let column = self.table.tableColumns.first(where: { $0.identifier.rawValue == "graph" }) {
                        column.width = max(column.width, min(240, CGFloat(self.graph.map(\.width).max() ?? 1)*15+24))
                    }
                    if self.worktreeManager?.window?.isVisible == true { self.worktreeManager?.reload() }
                    self.repoTitle.stringValue = URL(fileURLWithPath: repo.path).lastPathComponent
                    self.repoSubtitle.stringValue = repo.branch + (repo.worktrees.first { Git.samePath($0.path, repo.path) }.map { "  ·  " + $0.stateLabel } ?? "")
                    self.repoTitle.toolTip = repo.path
                    self.repoSubtitle.toolTip = repo.path + "  ·  " + self.repoSubtitle.stringValue
                    self.window?.title = self.repoTitle.stringValue + " — GitGraph Lite"
                    self.branchPins = Set(UserDefaults.standard.stringArray(forKey: self.branchPreferenceKey) ?? [])
                    self.updateBranchButton()
                    (self.branchPopover.contentViewController as? BranchPicker)?.rebuild()
                    UserDefaults.standard.set(repo.path, forKey: "lastRepository")
                    self.applySearch(selected: selected)
                    if switching || self.table.selectedRowIndexes.isEmpty {
                        if !self.visibleIndices.isEmpty {
                            let row = focusHead ? (self.visibleIndices.firstIndex { self.commits[$0].id == self.activeHead } ?? 0) : 0
                            self.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                            self.table.scrollRowToVisible(row)
                        }
                        else { self.clearDetails() }
                    }
                case .failure(let error):
                    self.footer.stringValue = "Could not load repository."
                    let alert = NSAlert(); alert.messageText = "Unable to open Git history"; alert.informativeText = error.localizedDescription
                    alert.beginSheetModal(for: self.window!)
                }
            }
        }
    }

    func checkForChanges() {
        guard !loading, !checking, !operationRunning, window?.attachedSheet == nil, let repo = repository else { return }
        checking = true
        DispatchQueue.global(qos: .utility).async {
            let signature = try? Git.signature(at: repo.path)
            let treeSignature = (try? Git.worktrees(at: repo.path)).map(Git.worktreeSummary)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }; self.checking = false
                guard self.repository?.path == repo.path, !self.loading, !self.operationRunning, self.window?.attachedSheet == nil else { return }
                if let signature, signature != repo.signature || (treeSignature != nil && treeSignature != repo.worktreeSignature) { self.refresh(path: repo.path) }
            }
        }
    }

    func controlTextDidChange(_ obj: Notification) { applySearch(selected: table.selectedRowIndexes.compactMap { commit(at: $0)?.id }) }

    func applySearch(selected: [String]) {
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matching = commits.indices.filter { i in
            let c = commits[i]
            return query.isEmpty || "\(c.subject) \(c.author) \(c.id) \(c.decorations)".lowercased().contains(query)
        }
        rebuildHistoryRows(matching: matching)
        rebuilding = true
        table.reloadData()
        let rows = IndexSet(visibleIndices.indices.filter { groupHeaders[$0] == nil && selected.contains(commits[visibleIndices[$0]].id) })
        table.selectRowIndexes(rows, byExtendingSelection: false)
        rebuilding = false
        footer.stringValue = query.isEmpty ? "\(commits.count) commits loaded · Updates automatically" : "\(visibleIndices.count) matches in \(commits.count) loaded commits · Graph connections hidden while searching"
        if query.isEmpty {
            let folded = historyGroups.filter { !isGroupExpanded($0.id) }
            if !folded.isEmpty { footer.stringValue += " · \(folded.count) groupes repliés (\(folded.reduce(0) { $0 + $1.indices.count }) commits)" }
        }
        more.isHidden = commits.count < limit
        if let operation = repository?.pendingOperation { footer.stringValue += " · \(operation) in progress — right-click for Continue / Abort" }
        if rows.isEmpty { clearDetails() } else { loadDetails() }
    }

    func commit(at row: Int) -> Commit? {
        guard visibleIndices.indices.contains(row), groupHeaders[row] == nil else { return nil }
        return commits[visibleIndices[row]]
    }
    func numberOfRows(in tableView: NSTableView) -> Int { tableView === table ? visibleIndices.count : fileRows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn else { return nil }
        let id = column.identifier
        if tableView === fileTable {
            return fileRowView(row)
        }
        if let group = groupHeaders[row] {
            if id.rawValue == "subject" { return groupView(group) }
            if id.rawValue == "graph" {
                let cell = GraphCell(); cell.row = visibleGraph[row]; cell.isGroup = true; return cell
            }
            return NSTextField(labelWithString: "")
        }
        guard let c = commit(at: row) else { return nil }
        switch id.rawValue {
        case "graph":
            let cell = (tableView.makeView(withIdentifier: id, owner: self) as? GraphCell) ?? GraphCell()
            cell.identifier = id; cell.row = visibleGraph[row]; cell.filtered = !search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            cell.isGroup = false; cell.isHead = c.id == activeHead; cell.toolTip = c.id + (cell.isHead ? " · Current worktree HEAD" : "")
            cell.needsDisplay = true; return cell
        case "subject":
            let cell = (tableView.makeView(withIdentifier: id, owner: self) as? CommitCell) ?? CommitCell()
            cell.identifier = id
            cell.configure(c, labels: labelsByCommit[c.id] ?? [], worktrees: (repository?.worktrees ?? []).filter { $0.head == c.id }, color: visibleGraph[row].color, isHead: c.id == activeHead)
            return cell
        default:
            let label = (tableView.makeView(withIdentifier: id, owner: self) as? NSTextField) ?? NSTextField(labelWithString: "")
            label.identifier = id; label.font = id.rawValue == "hash" ? .monospacedSystemFont(ofSize: 12, weight: .semibold) : .systemFont(ofSize: 10)
            label.textColor = id.rawValue == "hash" ? .labelColor : .secondaryLabelColor; label.lineBreakMode = .byTruncatingTail
            label.stringValue = id.rawValue == "author" ? c.author : id.rawValue == "date" ? dateFormatter.string(from: c.date) : String(c.id.prefix(10))
            label.toolTip = label.stringValue + (id.rawValue == "date" ? " · Commit date, local time" : ""); return label
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if tableView === fileTable { return fileRows.indices.contains(row) && !fileRows[row].isDirectory }
        return groupHeaders[row] == nil
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !rebuilding, let source = notification.object as? NSTableView else { return }
        if source === table { loadDetails() } else { loadPatch() }
    }

    func clearDetails() {
        detailID = UUID(); patchID = UUID(); target = nil; base = nil; files = []
        fileRows = []; fileTable.reloadData(); fileTitle.stringValue = "FILES"
        detailTitle.stringValue = commits.isEmpty ? "No commits yet" : "Select a commit to inspect its changes"
        message.string = ""; setDiff("")
    }

    func loadDetails() {
        let selected = table.selectedRowIndexes.compactMap { commit(at: $0) }
        guard let first = selected.first, repository != nil else { clearDetails(); return }
        guard selected.count <= 2 else {
            clearDetails(); detailTitle.stringValue = "Select one commit, or exactly two to compare"; return
        }
        showDetails(for: first, base: selected.count == 2 ? selected[1].id : nil)
    }

    func showDetails(for first: Commit, base comparisonBase: String?) {
        guard let repo = repository else { return }
        target = first.id; base = comparisonBase
        let base = self.base, request = UUID(); detailID = request; patchID = UUID()
        files = []; fileRows = []; fileTable.reloadData(); fileTitle.stringValue = "FILES"
        detailTitle.stringValue = base == nil ? "\(first.id.prefix(10))  ·  \(first.author)  ·  \(dateFormatter.string(from: first.date))" : "Compare \(base!.prefix(8)) → \(first.id.prefix(8))"
        message.string = "Loading…"; setDiff("")
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { () -> ([ChangedFile], String) in
                let files = try Git.files(at: repo.path, target: first.id, base: base)
                let text = base == nil ? try Git.message(at: repo.path, commit: first.id) : "Changes from \(base!) to \(first.id)\n\(first.subject)"
                return (files, text)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.detailID == request else { return }
                switch result {
                case .success(let (files, text)):
                    self.files = files; self.message.string = text; self.fileTitle.stringValue = "FILES · \(files.count)"
                    self.rebuildFileRows()
                    if files.isEmpty { self.setDiff("No file changes for this selection.") }
                case .failure(let error): self.message.string = error.localizedDescription
                }
            }
        }
    }

    func loadPatch() {
        let row = fileTable.selectedRow
        guard fileRows.indices.contains(row), let index = fileRows[row].fileIndex, let target, let repo = repository else { return }
        let file = files[index], base = self.base, request = UUID(); patchID = request
        setDiff("Loading \(file.path)…")
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try Git.patch(at: repo.path, target: target, base: base, file: file.path) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.patchID == request else { return }
                switch result {
                case .success(let patch):
                    self.diffViewer.show(patch: patch, file: file.path, before: base.map { String($0.prefix(8)) } ?? "Parent", after: String(target.prefix(8)))
                case .failure(let error): self.setDiff(error.localizedDescription)
                }
            }
        }
    }

    func setDiff(_ text: String) {
        diffViewer.showMessage(text)
    }

    @objc func focusSearch() { window?.makeFirstResponder(search) }
    @objc func copyCommitHash() {
        let ids = table.selectedRowIndexes.compactMap { commit(at: $0)?.id }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(ids.joined(separator: "\n"), forType: .string)
    }
    @objc func revealRepository() { if let path = repository?.path { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path) } }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: Controller!
    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = Controller(); buildMenu()
        controller.showWindow(nil); NSApp.activate(ignoringOtherApps: true)
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--repo"), args.indices.contains(i+1) { controller.open(args[i+1]) }
        else if let path = UserDefaults.standard.string(forKey: "lastRepository") { controller.open(path) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if controller == nil { controller = Controller(); buildMenu(); controller.showWindow(nil) }
        if let path = filenames.first { controller.open(path) }
        sender.reply(toOpenOrPrint: .success)
    }
    func buildMenu() {
        let menu = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(); item.title = title; let sub = NSMenu(title: title); item.submenu = sub; menu.addItem(item); return sub
        }
        let app = submenu("GitGraph Lite")
        app.addItem(withTitle: "About GitGraph Lite", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator()); app.addItem(withTitle: "Quit GitGraph Lite", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let file = submenu("File")
        let open = file.addItem(withTitle: "Open Repository…", action: #selector(Controller.openRepository), keyEquivalent: "o"); open.target = controller
        let reveal = file.addItem(withTitle: "Reveal in Finder", action: #selector(Controller.revealRepository), keyEquivalent: ""); reveal.target = controller
        let manage = file.addItem(withTitle: "Manage Worktrees…", action: #selector(Controller.showWorktreeManager), keyEquivalent: ""); manage.target = controller
        file.addItem(.separator()); file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let edit = submenu("Edit")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let copy = edit.addItem(withTitle: "Copy Commit Hash", action: #selector(Controller.copyCommitHash), keyEquivalent: "C"); copy.target = controller
        let view = submenu("View")
        let refresh = view.addItem(withTitle: "Refresh", action: #selector(Controller.refreshNow), keyEquivalent: "r"); refresh.target = controller
        let find = view.addItem(withTitle: "Find Commit", action: #selector(Controller.focusSearch), keyEquivalent: "f"); find.target = controller
        NSApp.mainMenu = menu
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
