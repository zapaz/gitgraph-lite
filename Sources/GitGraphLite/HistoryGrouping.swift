import AppKit
import GitGraphCore

extension Controller {
    @objc func groupingChanged(_ sender: NSButton) {
        let selected = table.selectedRowIndexes.compactMap { commit(at: $0)?.id }
        groupsFolded = sender.state == .on
        groupOverrides.removeAll()
        search.stringValue = ""
        UserDefaults.standard.set(groupsFolded, forKey: "groupCommits")
        applySearch(selected: selected)
    }
    func updateGroupingToggle() {
        groupingToggle.state = groupsFolded ? .on : .off
        groupingToggle.title = groupsFolded ? "Plié" : "Déplié"
    }
    func isGroupExpanded(_ id: String) -> Bool {
        groupsFolded ? groupOverrides.contains(id) : !groupOverrides.contains(id)
    }
    func rebuildHistoryRows(matching: [Int]) {
        groupHeaders.removeAll()
        let protected = Set((repository?.references.map(\.target) ?? []) + (repository?.worktrees.map(\.head) ?? []))
        historyGroups = HistoryGroup.make(commits, graph: graph, protected: protected)
        updateGroupingToggle()
        guard search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { visibleIndices = matching; return }
        let starts = Dictionary(uniqueKeysWithValues: historyGroups.map { ($0.indices.lowerBound, $0) })
        visibleIndices = []; var i = 0
        while i < commits.count {
            if let group = starts[i] {
                groupHeaders[visibleIndices.count] = group
                visibleIndices.append(i)
                if isGroupExpanded(group.id) { visibleIndices.append(contentsOf: group.indices) }
                i = group.indices.upperBound
            } else { visibleIndices.append(i); i += 1 }
        }
    }
    func groupView(_ group: HistoryGroup) -> NSView {
        let expanded = isGroupExpanded(group.id)
        let first = commits[group.indices.lowerBound], last = commits[group.indices.upperBound-1]
        let button = CallbackButton("\(expanded ? "▾" : "▸")  \(group.indices.count) commits  ·  \(first.subject) …") { [weak self] in
            guard let self else { return }
            let row = self.table.rows(in: self.table.visibleRect).location
            if self.groupOverrides.contains(group.id) { self.groupOverrides.remove(group.id) } else { self.groupOverrides.insert(group.id) }
            self.applySearch(selected: self.table.selectedRowIndexes.compactMap { self.commit(at: $0)?.id })
            if row < self.visibleIndices.count { self.table.scrollRowToVisible(row) }
        }
        button.isBordered = false; button.alignment = .left; button.font = .systemFont(ofSize: 11, weight: .semibold)
        button.contentTintColor = .secondaryLabelColor; button.lineBreakMode = .byTruncatingTail
        button.toolTip = "\(group.indices.count) linear commits · \(first.id.prefix(8)) … \(last.id.prefix(8))\nClick to \(expanded ? "collapse" : "expand"). References and junctions are never hidden."
        return button
    }
}
