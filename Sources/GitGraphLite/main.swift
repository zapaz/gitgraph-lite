import AppKit
import GitGraphCore

let palette: [NSColor] = [.systemTeal, .systemPurple, .systemOrange, .systemBlue, .systemPink, .systemGreen, .systemYellow]

final class GraphCell: NSView {
    var row: GraphRow?
    var filtered = false
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard let row else { return }
        let x: (Int) -> CGFloat = { 15 + CGFloat($0) * 16 }
        let mid = bounds.height / 2
        if !filtered {
            for edge in row.edges {
                let top: CGFloat = edge.segment == 2 ? mid : 0
                let bottom: CGFloat = edge.segment == 1 ? mid : bounds.height
                let path = NSBezierPath()
                path.move(to: NSPoint(x: x(edge.from), y: top))
                path.curve(to: NSPoint(x: x(edge.to), y: bottom), controlPoint1: NSPoint(x: x(edge.from), y: top + (bottom-top)*0.6), controlPoint2: NSPoint(x: x(edge.to), y: bottom - (bottom-top)*0.6))
                palette[edge.color % palette.count].withAlphaComponent(0.8).setStroke()
                path.lineWidth = 1.8; path.stroke()
            }
        }
        let dot = NSBezierPath(ovalIn: NSRect(x: x(filtered ? 0 : row.lane)-4, y: mid-4, width: 8, height: 8))
        palette[row.color % palette.count].setFill(); dot.fill()
        NSColor.windowBackgroundColor.setStroke(); dot.lineWidth = 1.2; dot.stroke()
    }
}

final class CommitCell: NSView {
    let stack = NSStackView()
    override init(frame: NSRect) {
        super.init(frame: frame)
        stack.orientation = .horizontal; stack.spacing = 6; stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4), stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6), stack.centerYAnchor.constraint(equalTo: centerYAnchor)])
    }
    required init?(coder: NSCoder) { fatalError() }
    func configure(_ commit: Commit) {
        for view in stack.arrangedSubviews { stack.removeArrangedSubview(view); view.removeFromSuperview() }
        if !commit.decorations.isEmpty {
            let refs = commit.decorations.replacingOccurrences(of: "HEAD -> ", with: "● ")
            let pill = NSTextField(labelWithString: " " + refs + " ")
            pill.font = .systemFont(ofSize: 10, weight: .semibold)
            pill.textColor = .systemTeal; pill.drawsBackground = true
            pill.backgroundColor = NSColor.systemTeal.withAlphaComponent(0.12)
            pill.wantsLayer = true; pill.layer?.cornerRadius = 4
            pill.lineBreakMode = .byTruncatingTail
            pill.widthAnchor.constraint(lessThanOrEqualToConstant: 260).isActive = true
            pill.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            stack.addArrangedSubview(pill)
        }
        let text = NSTextField(labelWithString: commit.subject)
        text.font = .systemFont(ofSize: 12)
        text.lineBreakMode = .byTruncatingTail
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(text)
        toolTip = commit.subject + "\n" + commit.decorations
    }
}

final class Controller: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    let table = NSTableView()
    let fileTable = NSTableView()
    let diff = NSTextView()
    let message = NSTextView()
    let repoTitle = NSTextField(labelWithString: "GitGraph Lite")
    let repoSubtitle = NSTextField(labelWithString: "A clear view of your history")
    let footer = NSTextField(labelWithString: "Open a local Git repository to begin.")
    let detailTitle = NSTextField(labelWithString: "Select a commit to inspect its changes")
    let fileTitle = NSTextField(labelWithString: "FILES")
    let search = NSSearchField()
    let branches = NSPopUpButton()
    let spinner = NSProgressIndicator()
    let more = NSButton(title: "Load more", target: nil, action: nil)
    var repository: Repository?
    var commits: [Commit] = []
    var graph: [GraphRow] = []
    var visibleIndices: [Int] = []
    var files: [ChangedFile] = []
    var branchFilter: String?
    var limit = 500
    var target: String?
    var base: String?
    var loadID = UUID(), detailID = UUID(), patchID = UUID()
    var loading = false, checking = false, rebuilding = false
    var timer: Timer?
    let dateFormatter: DateFormatter = { let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f }()

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

        let header = NSView(); header.heightAnchor.constraint(equalToConstant: 76).isActive = true
        let logo = NSImageView(image: NSImage(systemSymbolName: "point.3.connected.trianglepath.dotted", accessibilityDescription: "GitGraph Lite")!)
        logo.contentTintColor = .systemTeal
        logo.imageScaling = .scaleProportionallyUpOrDown
        let titles = NSStackView(views: [repoTitle, repoSubtitle]); titles.orientation = .vertical; titles.alignment = .leading; titles.spacing = 3
        repoTitle.font = .systemFont(ofSize: 19, weight: .semibold)
        repoSubtitle.font = .systemFont(ofSize: 11); repoSubtitle.textColor = .secondaryLabelColor
        repoSubtitle.lineBreakMode = .byTruncatingMiddle
        let open = NSButton(title: "Open Repository…", target: self, action: #selector(openRepository)); open.bezelStyle = .rounded
        let refresh = NSButton(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")!, target: self, action: #selector(refreshNow)); refresh.bezelStyle = .rounded; refresh.toolTip = "Refresh (⌘R)"
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        for view in [logo, titles, open, refresh, spinner] { view.translatesAutoresizingMaskIntoConstraints = false; header.addSubview(view) }
        NSLayoutConstraint.activate([
            logo.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20), logo.centerYAnchor.constraint(equalTo: header.centerYAnchor), logo.widthAnchor.constraint(equalToConstant: 30), logo.heightAnchor.constraint(equalToConstant: 30),
            titles.leadingAnchor.constraint(equalTo: logo.trailingAnchor, constant: 12), titles.centerYAnchor.constraint(equalTo: header.centerYAnchor), titles.trailingAnchor.constraint(lessThanOrEqualTo: spinner.leadingAnchor, constant: -20),
            open.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20), open.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            refresh.trailingAnchor.constraint(equalTo: open.leadingAnchor, constant: -8), refresh.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            spinner.trailingAnchor.constraint(equalTo: refresh.leadingAnchor, constant: -12), spinner.centerYAnchor.constraint(equalTo: header.centerYAnchor), spinner.widthAnchor.constraint(equalToConstant: 16), spinner.heightAnchor.constraint(equalToConstant: 16)
        ])
        outer.addArrangedSubview(header)
        outer.addArrangedSubview(separator())

        branches.addItem(withTitle: "All branches"); branches.target = self; branches.action = #selector(branchChanged)
        branches.widthAnchor.constraint(equalToConstant: 260).isActive = true
        search.placeholderString = "Search loaded commits, authors or hashes"; search.delegate = self
        search.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        let hint = NSTextField(labelWithString: "⌘-click two commits to compare"); hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
        let tools = NSStackView(views: [branches, search, hint]); tools.spacing = 14; tools.edgeInsets = NSEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        tools.heightAnchor.constraint(equalToConstant: 48).isActive = true
        tools.distribution = .fill; search.setContentHuggingPriority(.defaultLow, for: .horizontal)
        outer.addArrangedSubview(tools)

        table.delegate = self; table.dataSource = self
        table.rowHeight = 30; table.intercellSpacing = NSSize(width: 0, height: 0)
        table.allowsMultipleSelection = true; table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        for (id, title, width) in [("graph", "GRAPH", 140.0), ("subject", "COMMIT", 600.0), ("author", "AUTHOR", 150.0), ("date", "DATE", 110.0), ("hash", "HASH", 80.0)] {
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
        let fileHeader = NSStackView(views: [fileTitle]); fileHeader.edgeInsets = NSEdgeInsets(top: 9, left: 12, bottom: 9, right: 12)
        fileHeader.heightAnchor.constraint(equalToConstant: 32).isActive = true
        filePane.addArrangedSubview(fileHeader)
        fileTable.delegate = self; fileTable.dataSource = self; fileTable.rowHeight = 27; fileTable.headerView = nil
        let fileCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file")); fileCol.width = 260; fileTable.addTableColumn(fileCol)
        let fileScroll = NSScrollView(); fileScroll.hasVerticalScroller = true; fileScroll.documentView = fileTable
        filePane.addArrangedSubview(fileScroll)
        filePane.widthAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true
        bottom.addArrangedSubview(filePane)
        diff.isEditable = false; diff.isSelectable = true; diff.isRichText = false
        diff.frame = NSRect(x: 0, y: 0, width: 800, height: 250)
        diff.minSize = NSSize(width: 0, height: 0)
        diff.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        diff.font = .monospacedSystemFont(ofSize: 12, weight: .regular); diff.backgroundColor = .textBackgroundColor
        diff.textContainerInset = NSSize(width: 16, height: 12)
        diff.isHorizontallyResizable = true; diff.isVerticallyResizable = true
        diff.autoresizingMask = [.width]; diff.textContainer?.widthTracksTextView = false
        diff.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let diffScroll = NSScrollView(); diffScroll.hasVerticalScroller = true; diffScroll.hasHorizontalScroller = true; diffScroll.documentView = diff
        bottom.addArrangedSubview(diffScroll)
        details.addArrangedSubview(bottom)

        let split = NSSplitView(); split.isVertical = false; split.dividerStyle = .thin
        split.addArrangedSubview(graphScroll); split.addArrangedSubview(details)
        graphScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
        details.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        outer.addArrangedSubview(split)
        outer.addArrangedSubview(separator())
        footer.font = .systemFont(ofSize: 11); footer.textColor = .secondaryLabelColor
        footer.lineBreakMode = .byTruncatingMiddle
        let readOnly = NSTextField(labelWithString: "READ ONLY"); readOnly.font = .systemFont(ofSize: 9, weight: .semibold); readOnly.textColor = .systemTeal
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
            split.setPosition(split.bounds.height * 0.56, ofDividerAt: 0)
            bottom.setPosition(280, ofDividerAt: 0)
        }
        setDiff("Open a repository, then select a commit and a file.\n\nGitGraph Lite browses local history without modifying your repository.")
    }

    func separator() -> NSView {
        let line = NSBox(); line.boxType = .separator; line.heightAnchor.constraint(equalToConstant: 1).isActive = true; return line
    }

    @objc func openRepository() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.prompt = "Open Repository"
        panel.beginSheetModal(for: window!) { [weak self] response in
            if response == .OK, let path = panel.url?.path { self?.open(path) }
        }
    }

    func open(_ path: String) {
        limit = 500; branchFilter = nil; search.stringValue = ""
        refresh(path: path, switching: true)
    }
    @objc func refreshNow() { if let path = repository?.path { refresh(path: path) } else { openRepository() } }
    @objc func loadMore() { limit += 500; refreshNow() }
    @objc func branchChanged() {
        let i = branches.indexOfSelectedItem
        branchFilter = i > 0 ? repository?.branches[i-1] : nil
        limit = 500; refreshNow()
    }

    func refresh(path: String, switching: Bool = false) {
        let request = UUID(); loadID = request; loading = true; spinner.startAnimation(nil)
        let filter = branchFilter, count = limit
        footer.stringValue = "Loading history…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try Git.load(at: path, branch: filter, limit: count) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.loadID == request else { return }
                self.loading = false; self.spinner.stopAnimation(nil)
                switch result {
                case .success(let repo):
                    let selected = switching ? [] : self.table.selectedRowIndexes.compactMap { self.commit(at: $0)?.id }
                    self.repository = repo; self.commits = repo.commits; self.graph = GraphLayout.make(repo.commits)
                    self.repoTitle.stringValue = URL(fileURLWithPath: repo.path).lastPathComponent
                    self.repoSubtitle.stringValue = repo.path + "  ·  " + repo.branch
                    self.repoSubtitle.toolTip = repo.path
                    self.window?.title = self.repoTitle.stringValue + " — GitGraph Lite"
                    self.branches.removeAllItems(); self.branches.addItem(withTitle: "All branches")
                    self.branches.addItems(withTitles: repo.branches.map { $0.replacingOccurrences(of: "refs/heads/", with: "").replacingOccurrences(of: "refs/remotes/", with: "") })
                    if let filter, let i = repo.branches.firstIndex(of: filter) { self.branches.selectItem(at: i+1) }
                    UserDefaults.standard.set(repo.path, forKey: "lastRepository")
                    self.applySearch(selected: selected)
                    if switching || self.table.selectedRowIndexes.isEmpty {
                        if !self.visibleIndices.isEmpty { self.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
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
        guard !loading, !checking, let repo = repository else { return }
        checking = true
        DispatchQueue.global(qos: .utility).async {
            let signature = try? Git.signature(at: repo.path)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }; self.checking = false
                guard self.repository?.path == repo.path, !self.loading else { return }
                if let signature, signature != repo.signature { self.refresh(path: repo.path) }
            }
        }
    }

    func controlTextDidChange(_ obj: Notification) { applySearch(selected: table.selectedRowIndexes.compactMap { commit(at: $0)?.id }) }

    func applySearch(selected: [String]) {
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        visibleIndices = commits.indices.filter { i in
            let c = commits[i]
            return query.isEmpty || "\(c.subject) \(c.author) \(c.id) \(c.decorations)".lowercased().contains(query)
        }
        rebuilding = true
        table.reloadData()
        let rows = IndexSet(visibleIndices.indices.filter { selected.contains(commits[visibleIndices[$0]].id) })
        table.selectRowIndexes(rows, byExtendingSelection: false)
        rebuilding = false
        footer.stringValue = query.isEmpty ? "\(commits.count) commits loaded · Updates automatically" : "\(visibleIndices.count) matches in \(commits.count) loaded commits · Graph connections hidden while searching"
        more.isHidden = commits.count < limit
        if rows.isEmpty { clearDetails() } else { loadDetails() }
    }

    func commit(at row: Int) -> Commit? {
        guard visibleIndices.indices.contains(row) else { return nil }
        return commits[visibleIndices[row]]
    }
    func numberOfRows(in tableView: NSTableView) -> Int { tableView === table ? visibleIndices.count : files.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn else { return nil }
        let id = column.identifier
        if tableView === fileTable {
            let file = files[row]
            let label = (tableView.makeView(withIdentifier: id, owner: self) as? NSTextField) ?? NSTextField(labelWithString: "")
            label.identifier = id; label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            label.stringValue = "\(file.status)  \(file.path)"; label.lineBreakMode = .byTruncatingMiddle; label.toolTip = file.path
            label.textColor = file.status == "A" ? .systemGreen : file.status == "D" ? .systemRed : .labelColor
            return label
        }
        guard let c = commit(at: row) else { return nil }
        switch id.rawValue {
        case "graph":
            let cell = (tableView.makeView(withIdentifier: id, owner: self) as? GraphCell) ?? GraphCell()
            cell.identifier = id; cell.row = graph[visibleIndices[row]]; cell.filtered = !search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            cell.needsDisplay = true; return cell
        case "subject":
            let cell = (tableView.makeView(withIdentifier: id, owner: self) as? CommitCell) ?? CommitCell()
            cell.identifier = id; cell.configure(c); return cell
        default:
            let label = (tableView.makeView(withIdentifier: id, owner: self) as? NSTextField) ?? NSTextField(labelWithString: "")
            label.identifier = id; label.font = id.rawValue == "hash" ? .monospacedSystemFont(ofSize: 11, weight: .regular) : .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor; label.lineBreakMode = .byTruncatingTail
            label.stringValue = id.rawValue == "author" ? c.author : id.rawValue == "date" ? dateFormatter.string(from: c.date) : String(c.id.prefix(8))
            label.toolTip = label.stringValue; return label
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !rebuilding, let source = notification.object as? NSTableView else { return }
        if source === table { loadDetails() } else { loadPatch() }
    }

    func clearDetails() {
        detailID = UUID(); patchID = UUID(); target = nil; base = nil; files = []
        fileTable.reloadData(); fileTitle.stringValue = "FILES"
        detailTitle.stringValue = commits.isEmpty ? "No commits yet" : "Select a commit to inspect its changes"
        message.string = ""; setDiff("")
    }

    func loadDetails() {
        let selected = table.selectedRowIndexes.compactMap { commit(at: $0) }
        guard let first = selected.first, let repo = repository else { clearDetails(); return }
        guard selected.count <= 2 else {
            clearDetails(); detailTitle.stringValue = "Select one commit, or exactly two to compare"; return
        }
        target = first.id; base = selected.count == 2 ? selected[1].id : nil
        let base = self.base, request = UUID(); detailID = request; patchID = UUID()
        files = []; fileTable.reloadData(); fileTitle.stringValue = "FILES"
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
                    self.fileTable.reloadData()
                    if !files.isEmpty { self.fileTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
                    else { self.setDiff("No file changes for this selection.") }
                case .failure(let error): self.message.string = error.localizedDescription
                }
            }
        }
    }

    func loadPatch() {
        let row = fileTable.selectedRow
        guard files.indices.contains(row), let target, let repo = repository else { return }
        let file = files[row], base = self.base, request = UUID(); patchID = request
        setDiff("Loading \(file.path)…")
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try Git.patch(at: repo.path, target: target, base: base, file: file.path) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.patchID == request else { return }
                switch result {
                case .success(let patch): self.setDiff(patch.isEmpty ? "No text diff available." : patch)
                case .failure(let error): self.setDiff(error.localizedDescription)
                }
            }
        }
    }

    func setDiff(_ text: String) {
        let result = NSMutableAttributedString(string: text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.labelColor])
        let ns = text as NSString
        var offset = 0
        while offset < ns.length {
            let range = ns.lineRange(for: NSRange(location: offset, length: 0))
            let line = ns.substring(with: range)
            let color: NSColor?
            if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff ") || line.hasPrefix("index ") { color = .secondaryLabelColor }
            else if line.hasPrefix("+") { color = .systemGreen }
            else if line.hasPrefix("-") { color = .systemRed }
            else if line.hasPrefix("@@") { color = .systemTeal }
            else { color = nil }
            if let color { result.addAttribute(.foregroundColor, value: color, range: range) }
            offset = NSMaxRange(range)
        }
        diff.textStorage?.setAttributedString(result); diff.scrollToBeginningOfDocument(nil)
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
