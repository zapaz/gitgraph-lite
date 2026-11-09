import AppKit
import GitGraphCore

/// One row of the changed-files list: indent guides, chevron and folder icon for
/// folders; file icon, name (with its folder in Paths mode) and a status letter for files.
final class FileRowCell: NSView {
    static let indentStep: CGFloat = 14, leftInset: CGFloat = 8
    let depth: Int

    init(row: FileTreeRow, file: ChangedFile?, tree: Bool, expanded: Bool) {
        depth = row.depth
        super.init(frame: .zero)
        let x = Self.leftInset + CGFloat(depth) * Self.indentStep
        let stack = NSStackView(); stack.orientation = .horizontal; stack.alignment = .centerY; stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        func symbol(_ name: String, _ size: CGFloat, _ color: NSColor, weight: NSFont.Weight = .regular) -> NSImageView {
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: size, weight: weight))
            let view = NSImageView(image: image ?? NSImage()); view.contentTintColor = color
            view.widthAnchor.constraint(equalToConstant: 14).isActive = true
            return view
        }
        let name = NSTextField(labelWithString: row.name); name.lineBreakMode = .byTruncatingMiddle
        name.setContentCompressionResistancePriority(.init(250), for: .horizontal)
        toolTip = row.path
        if let file {
            if tree { stack.addArrangedSubview(symbol("chevron.right", 8, .clear)) }
            let color = Self.color(file.status)
            stack.addArrangedSubview(symbol(file.status == "D" ? "doc" : "doc.text", 11, color == .labelColor ? .secondaryLabelColor : color))
            name.font = .systemFont(ofSize: 12); name.textColor = color
            if tree { name.stringValue = row.name } else { name.stringValue = (row.path as NSString).lastPathComponent }
            if file.status == "D" {
                name.attributedStringValue = NSAttributedString(string: name.stringValue, attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: color, .font: NSFont.systemFont(ofSize: 12)])
            }
            stack.addArrangedSubview(name)
            let folder = (row.path as NSString).deletingLastPathComponent
            if !tree && !folder.isEmpty {
                let dir = NSTextField(labelWithString: folder); dir.font = .systemFont(ofSize: 11); dir.textColor = .tertiaryLabelColor
                dir.lineBreakMode = .byTruncatingHead; dir.setContentCompressionResistancePriority(.init(200), for: .horizontal)
                stack.addArrangedSubview(dir)
            }
            let spacer = NSView(); spacer.setContentHuggingPriority(.init(1), for: .horizontal)
            spacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)
            stack.addArrangedSubview(spacer)
            let badge = NSTextField(labelWithString: file.status); badge.font = .monospacedSystemFont(ofSize: 10, weight: .bold)
            badge.textColor = color == .labelColor ? .secondaryLabelColor : color; badge.alignment = .center
            badge.toolTip = Self.statusName(file.status)
            badge.setContentCompressionResistancePriority(.required, for: .horizontal)
            stack.addArrangedSubview(badge)
        } else {
            stack.addArrangedSubview(symbol(expanded ? "chevron.down" : "chevron.right", 8, .secondaryLabelColor, weight: .semibold))
            stack.addArrangedSubview(symbol(expanded ? "folder" : "folder.fill", 11, .systemTeal))
            name.font = .systemFont(ofSize: 12, weight: .medium); name.textColor = .labelColor
            stack.addArrangedSubview(name)
            toolTip = row.path + (expanded ? " · Click to fold" : " · Click to unfold")
        }
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: x), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10), stack.centerYAnchor.constraint(equalTo: centerYAnchor)])
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Thin vertical guides, one per parent folder level.
    override func draw(_ dirtyRect: NSRect) {
        guard depth > 0 else { return }
        NSColor.separatorColor.withAlphaComponent(0.6).setFill()
        for level in 0..<depth {
            NSRect(x: Self.leftInset + CGFloat(level) * Self.indentStep + 6.5, y: 0, width: 1, height: bounds.height).fill()
        }
    }

    static func color(_ status: String) -> NSColor {
        switch status.first {
        case "A": return .systemGreen
        case "D": return .systemRed
        default: return .labelColor
        }
    }
    static func statusName(_ status: String) -> String {
        switch status.first {
        case "A": return "Added"
        case "D": return "Deleted"
        case "M": return "Modified"
        case "T": return "Type changed"
        default: return status
        }
    }
}

extension Controller {
    @objc func fileModeChanged() {
        fileTreeMode = fileMode.selectedSegment == 0
        UserDefaults.standard.set(fileTreeMode, forKey: "fileTreeMode")
        rebuildFileRows()
    }
    /// A click on a folder row folds or unfolds it.
    @objc func fileRowClicked() {
        let row = fileTable.clickedRow
        guard fileRows.indices.contains(row), fileRows[row].isDirectory else { return }
        let path = fileRows[row].path
        if collapsedDirectories.contains(path) { collapsedDirectories.remove(path) } else { collapsedDirectories.insert(path) }
        rebuildFileRows()
    }
    func rebuildFileRows() {
        let path = fileRows.indices.contains(fileTable.selectedRow) ? fileRows[fileTable.selectedRow].path : nil
        fileRows = FileTreeRow.make(files, tree: fileTreeMode, collapsed: collapsedDirectories)
        fileTable.reloadData()
        let selection = path.flatMap { path in fileRows.firstIndex { $0.path == path && !$0.isDirectory } } ?? fileRows.firstIndex { !$0.isDirectory }
        if let selection {
            let unchangedRow = fileTable.selectedRow == selection
            fileTable.selectRowIndexes(IndexSet(integer: selection), byExtendingSelection: false)
            if unchangedRow { loadPatch() }
        }
        else { fileTable.deselectAll(nil); setDiff("Select a file to inspect its changes.") }
    }
    func fileRowView(_ row: Int) -> NSView? {
        guard fileRows.indices.contains(row) else { return nil }
        let item = fileRows[row]
        return FileRowCell(row: item, file: item.fileIndex.map { files[$0] }, tree: fileTreeMode, expanded: !collapsedDirectories.contains(item.path))
    }
}
