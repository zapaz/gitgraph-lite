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
        guard search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            visibleIndices = matching; visibleGraph = matching.map { graph[$0] }; return
        }
        let projection = HistoryProjection.make(commits, groups: historyGroups, expanded: Set(historyGroups.filter { isGroupExpanded($0.id) }.map(\.id)))
        visibleIndices = projection.indices; groupHeaders = projection.headers; visibleGraph = projection.graph
    }
    func groupView(_ group: HistoryGroup) -> NSView {
        let expanded = isGroupExpanded(group.id)
        let first = commits[group.indices[0]], last = commits[group.indices.last!]
        let button = CallbackButton("\(expanded ? "▾" : "▸")  \(group.indices.count) commits \(expanded ? "dépliés" : "repliés")  ·  \(first.subject) …") { [weak self] in
            guard let self else { return }
            let row = self.table.rows(in: self.table.visibleRect).location
            if self.groupOverrides.contains(group.id) { self.groupOverrides.remove(group.id) } else { self.groupOverrides.insert(group.id) }
            self.applySearch(selected: self.table.selectedRowIndexes.compactMap { self.commit(at: $0)?.id })
            if row < self.visibleIndices.count { self.table.scrollRowToVisible(row) }
        }
        button.isBordered = false; button.alignment = .left; button.font = .systemFont(ofSize: 11, weight: .semibold)
        button.contentTintColor = .controlAccentColor; button.lineBreakMode = .byTruncatingTail
        button.toolTip = "\(group.indices.count) linear commits · \(first.id.prefix(8)) … \(last.id.prefix(8))\nClick to \(expanded ? "collapse" : "expand"). References and junctions are never hidden."
        return button
    }
}
