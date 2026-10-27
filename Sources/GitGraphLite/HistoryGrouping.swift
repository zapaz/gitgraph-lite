import AppKit
import GitGraphCore

extension Controller {
    @objc func groupingChanged() {
        let index = groupingPicker.indexOfSelectedItem
        if index == 0 { groupingEnabled = false }
        else {
            groupingEnabled = true
            if index == 1 { expandedGroups.removeAll() }
            else { expandedGroups = Set(historyGroups.map(\.id)) }
        }
        UserDefaults.standard.set(groupingEnabled, forKey: "groupCommits")
        applySearch(selected: table.selectedRowIndexes.compactMap { commit(at: $0)?.id })
    }
    func rebuildHistoryRows(matching: [Int], selected: [String]) {
        groupHeaders.removeAll()
        let protected = Set((repository?.references.map(\.target) ?? []) + (repository?.worktrees.map(\.head) ?? []) + selected)
        historyGroups = HistoryGroup.make(commits, graph: graph, protected: protected)
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
