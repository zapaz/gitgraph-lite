import AppKit
import GitGraphCore

extension Controller {
    @objc func groupingChanged(_ sender: NSMenuItem) {
        let selected = table.selectedRowIndexes.compactMap { commit(at: $0)?.id }
        switch sender.tag {
        case 0: groupingEnabled = false
        case 1: groupingEnabled = true; expandedGroups.removeAll()
        default: groupingEnabled = true; expandedGroups = Set(historyGroups.map(\.id))
        }
        UserDefaults.standard.set(groupingEnabled, forKey: "groupCommits")
        applySearch(selected: selected)
    }
    func updateGroupingPicker() {
        let ids = Set(historyGroups.map(\.id))
        let expanded = expandedGroups.intersection(ids)
        let title = !groupingEnabled ? "Groups: Off" : expanded.isEmpty ? "Groups: Collapsed" : expanded == ids ? "Groups: Expanded" : "Groups: Mixed"
        groupingPicker.item(at: 0)?.title = title
        for item in groupingPicker.itemArray.dropFirst() {
            item.state = (!groupingEnabled && item.tag == 0) || (groupingEnabled && expanded.isEmpty && item.tag == 1) || (groupingEnabled && !ids.isEmpty && expanded == ids && item.tag == 2) ? .on : .off
        }
    }
    func rebuildHistoryRows(matching: [Int]) {
        groupHeaders.removeAll()
        let protected = Set((repository?.references.map(\.target) ?? []) + (repository?.worktrees.map(\.head) ?? []))
        historyGroups = HistoryGroup.make(commits, graph: graph, protected: protected)
        updateGroupingPicker()
        guard groupingEnabled, search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { visibleIndices = matching; return }
        let starts = Dictionary(uniqueKeysWithValues: historyGroups.map { ($0.indices.lowerBound, $0) })
        visibleIndices = []; var i = 0
        while i < commits.count {
            if let group = starts[i] {
                groupHeaders[visibleIndices.count] = group
                visibleIndices.append(i)
                if expandedGroups.contains(group.id) { visibleIndices.append(contentsOf: group.indices) }
                i = group.indices.upperBound
            } else { visibleIndices.append(i); i += 1 }
        }
    }
    func groupView(_ group: HistoryGroup) -> NSView {
        let expanded = expandedGroups.contains(group.id)
        let first = commits[group.indices.lowerBound], last = commits[group.indices.upperBound-1]
        let button = CallbackButton("\(expanded ? "▾" : "▸")  \(group.indices.count) commits  ·  \(first.subject) …") { [weak self] in
            guard let self else { return }
            let row = self.table.rows(in: self.table.visibleRect).location
            if self.expandedGroups.contains(group.id) { self.expandedGroups.remove(group.id) } else { self.expandedGroups.insert(group.id) }
            self.applySearch(selected: self.table.selectedRowIndexes.compactMap { self.commit(at: $0)?.id })
            if row < self.visibleIndices.count { self.table.scrollRowToVisible(row) }
        }
        button.isBordered = false; button.alignment = .left; button.font = .systemFont(ofSize: 11, weight: .semibold)
        button.contentTintColor = .secondaryLabelColor; button.lineBreakMode = .byTruncatingTail
        button.toolTip = "\(group.indices.count) linear commits · \(first.id.prefix(8)) … \(last.id.prefix(8))\nClick to \(expanded ? "collapse" : "expand"). References and junctions are never hidden."
        return button
    }
}
