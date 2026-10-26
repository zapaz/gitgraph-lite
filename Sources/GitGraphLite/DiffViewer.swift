import AppKit
import GitGraphCore

private final class DiffCell: NSView {
    let label = NSTextField(labelWithString: "")
    var fill: NSColor = .clear
    var placeholder = false
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.isSelectable = true; label.lineBreakMode = .byClipping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8), label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6), label.centerYAnchor.constraint(equalTo: centerYAnchor)])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: bounds).addClip()
        fill.setFill(); bounds.fill()
        NSColor.separatorColor.withAlphaComponent(0.35).setFill()
        NSRect(x: bounds.maxX-1, y: 0, width: 1, height: bounds.height).fill()
        if placeholder {
            NSColor.separatorColor.withAlphaComponent(0.25).setStroke()
            let path = NSBezierPath()
            var x: CGFloat = -bounds.height
            while x < bounds.width { path.move(to: NSPoint(x: x, y: 0)); path.line(to: NSPoint(x: x+bounds.height, y: bounds.height)); x += 10 }
            path.lineWidth = 0.5; path.stroke()
        }
    }
}

final class DiffViewer: NSView, NSTableViewDataSource, NSTableViewDelegate {
    let table = NSTableView()
    let afterTable = NSTableView()
    let sideScroll = NSScrollView()
    let afterScroll = NSScrollView()
    let sides = NSStackView()
    let unifiedScroll = NSScrollView()
    let unified = NSTextView()
    let title = NSTextField(labelWithString: "DIFF")
    let stats = NSTextField(labelWithString: "")
    let empty = NSTextField(wrappingLabelWithString: "Select a file to view its changes")
    let mode = NSSegmentedControl(labels: ["Side by side", "Unified"], trackingMode: .selectOne, target: nil, action: nil)
    let previous = NSButton(), next = NSButton()
    var model = VisualDiff.parse("")
    var patch = ""
    var currentChange = -1
    var preferredWidth: CGFloat = 0
    var syncingScroll = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        title.font = .systemFont(ofSize: 11, weight: .semibold); title.lineBreakMode = .byTruncatingMiddle
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stats.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        mode.selectedSegment = UserDefaults.standard.integer(forKey: "diffMode")
        mode.target = self; mode.action = #selector(diffModeChanged); mode.controlSize = .small
        mode.widthAnchor.constraint(equalToConstant: 150).isActive = true
        previous.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Previous change")
        next.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Next change")
        for button in [previous, next] { button.bezelStyle = .rounded; button.controlSize = .small; button.target = self; button.widthAnchor.constraint(equalToConstant: 26).isActive = true }
        previous.action = #selector(previousChange); next.action = #selector(nextChange)
        previous.toolTip = "Previous change"; next.toolTip = "Next change"
        let header = NSStackView(views: [title, stats, previous, next, mode]); header.spacing = 8
        header.distribution = .fill
        header.edgeInsets = NSEdgeInsets(top: 5, left: 12, bottom: 5, right: 10)
        header.translatesAutoresizingMaskIntoConstraints = false; addSubview(header)
        NSLayoutConstraint.activate([header.leadingAnchor.constraint(equalTo: leadingAnchor), header.trailingAnchor.constraint(equalTo: trailingAnchor), header.topAnchor.constraint(equalTo: topAnchor), header.heightAnchor.constraint(equalToConstant: 36)])
        for view in [table, afterTable] {
            view.delegate = self; view.dataSource = self; view.rowHeight = 22
            view.intercellSpacing = .zero; view.columnAutoresizingStyle = .noColumnAutoresizing
            view.selectionHighlightStyle = .none; view.allowsColumnReordering = false
        }
        for (id, text, width) in [("oldNumber", "", 48.0), ("old", "BEFORE", 400.0), ("newNumber", "", 48.0), ("new", "AFTER", 400.0)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); c.title = text; c.width = width; c.minWidth = width; c.resizingMask = []
            (id.hasPrefix("old") ? table : afterTable).addTableColumn(c)
        }
        sideScroll.documentView = table; sideScroll.hasVerticalScroller = true; sideScroll.hasHorizontalScroller = true
        afterScroll.documentView = afterTable; afterScroll.hasVerticalScroller = true; afterScroll.hasHorizontalScroller = true
        sides.orientation = .horizontal; sides.distribution = .fillEqually; sides.alignment = .top; sides.spacing = 1
        sides.addArrangedSubview(sideScroll); sides.addArrangedSubview(afterScroll)
        for scroll in [sideScroll, afterScroll] {
            scroll.heightAnchor.constraint(equalTo: sides.heightAnchor).isActive = true
            scroll.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(scrollChanged(_:)), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        }
        unified.isEditable = false; unified.isRichText = false; unified.isSelectable = true
        unified.frame = NSRect(x: 0, y: 0, width: 800, height: 300)
        unified.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        unified.textContainerInset = NSSize(width: 14, height: 12)
        unified.isHorizontallyResizable = true; unified.isVerticallyResizable = true; unified.autoresizingMask = [.width]
        unified.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        unified.textContainer?.widthTracksTextView = false
        unified.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        unifiedScroll.documentView = unified; unifiedScroll.hasVerticalScroller = true; unifiedScroll.hasHorizontalScroller = true
        for view in [sides, unifiedScroll] {
            view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view)
            NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: leadingAnchor), view.trailingAnchor.constraint(equalTo: trailingAnchor), view.topAnchor.constraint(equalTo: header.bottomAnchor), view.bottomAnchor.constraint(equalTo: bottomAnchor)])
        }
        empty.textColor = .secondaryLabelColor; empty.font = .systemFont(ofSize: 12); empty.alignment = .center
        empty.translatesAutoresizingMaskIntoConstraints = false; addSubview(empty)
        NSLayoutConstraint.activate([empty.centerXAnchor.constraint(equalTo: centerXAnchor), empty.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 18), empty.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -50)])
        updateVisibility()
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); sizeColumns() }
    func sizeColumns() {
        for (scroll, table) in [(sideScroll, table), (afterScroll, afterTable)] {
            let width = max(200, scroll.contentSize.width-48, preferredWidth)
            table.tableColumns[1].minWidth = 100; table.tableColumns[1].width = width
        }
    }
    @objc func scrollChanged(_ notification: Notification) {
        guard !syncingScroll, let clip = notification.object as? NSClipView else { return }
        syncingScroll = true; defer { syncingScroll = false }
        let other = clip === sideScroll.contentView ? afterScroll : sideScroll
        other.contentView.scroll(to: NSPoint(x: other.contentView.bounds.origin.x, y: clip.bounds.origin.y))
        other.reflectScrolledClipView(other.contentView)
    }
    func showMessage(_ text: String) {
        patch = ""; model = .parse(""); title.stringValue = "DIFF"; stats.stringValue = ""
        empty.stringValue = text.isEmpty ? "Select a file to view its changes" : text
        table.reloadData(); afterTable.reloadData(); unified.string = text; updateVisibility()
    }
    func show(patch: String, file: String, before: String, after: String) {
        self.patch = patch; model = .parse(patch); currentChange = -1
        title.stringValue = file; title.toolTip = file
        table.tableColumns[1].title = "BEFORE · " + before
        afterTable.tableColumns[1].title = "AFTER · " + after
        let text = NSMutableAttributedString(string: "+\(model.additions)  −\(model.deletions)", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor.systemGreen])
        let ns = text.string as NSString
        text.addAttribute(.foregroundColor, value: NSColor.systemRed, range: ns.range(of: "−\(model.deletions)"))
        stats.attributedStringValue = text
        preferredWidth = min(8000, CGFloat(model.rows.map { max($0.oldText?.count ?? 0, $0.newText?.count ?? 0) }.max() ?? 0)*7.3 + 24)
        sizeColumns(); table.reloadData(); afterTable.reloadData(); table.scroll(.zero); afterTable.scroll(.zero)
        setUnified(patch)
        empty.stringValue = model.isBinary ? "Binary file changed. Switch to Unified for Git's summary." : "No text changes to display. Switch to Unified for details."
        updateVisibility()
    }
    func updateVisibility() {
        let split = mode.selectedSegment == 0
        sides.isHidden = !split; unifiedScroll.isHidden = split
        empty.isHidden = !split || !model.rows.isEmpty
        previous.isEnabled = !model.changeStarts.isEmpty; next.isEnabled = previous.isEnabled
    }
    @objc func diffModeChanged() { UserDefaults.standard.set(mode.selectedSegment, forKey: "diffMode"); updateVisibility() }
    @objc func previousChange() { navigate(-1) }
    @objc func nextChange() { navigate(1) }
    func navigate(_ direction: Int) {
        guard !model.changeStarts.isEmpty else { return }
        currentChange = currentChange < 0 ? (direction > 0 ? 0 : model.changeStarts.count-1) : (currentChange + direction + model.changeStarts.count) % model.changeStarts.count
        mode.selectedSegment = 0; updateVisibility()
        let row = model.changeStarts[currentChange]
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
        next.toolTip = "Change \(currentChange+1) of \(model.changeStarts.count)"
    }
    func numberOfRows(in tableView: NSTableView) -> Int { model.rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn else { return nil }
        let item = model.rows[row], old = column.identifier.rawValue.hasPrefix("old"), gutter = column.identifier.rawValue.hasSuffix("Number")
        let cell = (tableView.makeView(withIdentifier: column.identifier, owner: self) as? DiffCell) ?? DiffCell()
        cell.identifier = column.identifier
        let content = old ? item.oldText : item.newText
        let changed = item.kind == .change && content != nil
        let color: NSColor = old ? .systemRed : .systemGreen
        cell.fill = item.kind == .hunk ? NSColor.systemTeal.withAlphaComponent(0.09) : changed ? color.withAlphaComponent(gutter ? 0.17 : 0.10) : content == nil && item.kind == .change ? NSColor.quaternaryLabelColor.withAlphaComponent(0.12) : gutter ? NSColor.controlBackgroundColor : NSColor.textBackgroundColor
        cell.placeholder = !gutter && content == nil && item.kind == .change
        if gutter {
            cell.label.alignment = .right
            cell.label.textColor = changed ? color : .tertiaryLabelColor
            cell.label.stringValue = (old ? item.oldNumber : item.newNumber).map(String.init) ?? ""
        } else {
            cell.label.alignment = .left
            let display = (content ?? "").replacingOccurrences(of: "\t", with: "    ").replacingOccurrences(of: "\r", with: "␍")
            let styled = NSMutableAttributedString(string: display, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: item.kind == .hunk ? NSColor.systemTeal : item.kind == .note ? NSColor.secondaryLabelColor : NSColor.labelColor])
            if let range = old ? item.oldHighlight : item.newHighlight, let content {
                // Map UTF-16 offsets after expanding tabs for display.
                let ns = content as NSString
                let prefix = ns.substring(to: range.location).replacingOccurrences(of: "\t", with: "    ")
                let middle = ns.substring(with: range).replacingOccurrences(of: "\t", with: "    ")
                styled.addAttribute(.backgroundColor, value: color.withAlphaComponent(0.27), range: NSRange(location: prefix.utf16.count, length: middle.utf16.count))
            }
            cell.label.attributedStringValue = styled
        }
        cell.toolTip = gutter ? nil : content; cell.needsDisplay = true
        return cell
    }
    func setUnified(_ patch: String) {
        let result = NSMutableAttributedString(string: patch, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.labelColor])
        let ns = patch as NSString; var offset = 0
        while offset < ns.length {
            let range = ns.lineRange(for: NSRange(location: offset, length: 0)), line = ns.substring(with: range)
            if line.hasPrefix("+") && !line.hasPrefix("+++") { result.addAttribute(.backgroundColor, value: NSColor.systemGreen.withAlphaComponent(0.12), range: range) }
            else if line.hasPrefix("-") && !line.hasPrefix("---") { result.addAttribute(.backgroundColor, value: NSColor.systemRed.withAlphaComponent(0.12), range: range) }
            else if line.hasPrefix("@@") { result.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: range) }
            offset = NSMaxRange(range)
        }
        unified.textStorage?.setAttributedString(result); unified.scrollToBeginningOfDocument(nil)
    }
}
