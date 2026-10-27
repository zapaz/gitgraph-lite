import AppKit
import GitGraphCore

extension Controller {
    @objc func fileModeChanged() {
        fileTreeMode = fileMode.selectedSegment == 0
        UserDefaults.standard.set(fileTreeMode, forKey: "fileTreeMode")
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
        let name = fileTreeMode ? (item.path as NSString).lastPathComponent : item.path
        let indent = String(repeating: "  ", count: item.depth)
        if item.isDirectory {
            let button = CallbackButton(indent + (collapsedDirectories.contains(item.path) ? "▸  " : "▾  ") + name) { [weak self] in
                guard let self else { return }
                if self.collapsedDirectories.contains(item.path) { self.collapsedDirectories.remove(item.path) } else { self.collapsedDirectories.insert(item.path) }
                self.rebuildFileRows()
            }
            button.isBordered = false; button.alignment = .left; button.font = .monospacedSystemFont(ofSize: 11, weight: .semibold); button.lineBreakMode = .byTruncatingMiddle; button.toolTip = item.path
            return button
        }
        let file = files[item.fileIndex!]
        let label = NSTextField(labelWithString: indent + (fileTreeMode ? "    " : "") + file.status + "  " + name)
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular); label.lineBreakMode = .byTruncatingMiddle; label.toolTip = file.path
        label.textColor = file.status == "A" ? .systemGreen : file.status == "D" ? .systemRed : .labelColor
        return label
    }
}
