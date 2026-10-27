import AppKit
import GitGraphCore

extension Controller {
    @objc func groupingChanged(_ sender: NSButton) {
        let selected = table.selectedRowIndexes.compactMap { commit(at: $0)?.id }
        groupsFolded = sender.state == .on
        expandedGroups.removeAll(); collapsedGroups.removeAll()
        search.stringValue = ""
        UserDefaults.standard.set(groupsFolded, forKey: "groupCommits")
        applySearch(selected: selected)
    }
    func isGroupFolded(_ id: String) -> Bool {
        groupsFolded ? !expandedGroups.contains(id) : collapsedGroups.contains(id)
    }
    func foldGroup(_ id: String) { setGroupFolded(id, folded: true) }
    func unfoldGroup(_ id: String) { setGroupFolded(id, folded: false) }
    private func setGroupFolded(_ id: String, folded: Bool) {
        guard search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              historyGroups.contains(where: { $0.id == id }), isGroupFolded(id) != folded else { return }
        let selected = table.selectedRowIndexes.compactMap { commit(at: $0)?.id }
        if groupsFolded {
            if folded { expandedGroups.remove(id) } else { expandedGroups.insert(id) }
        } else {
            if folded { collapsedGroups.insert(id) } else { collapsedGroups.remove(id) }
        }
        applySearch(selected: selected)
    }
    func updateGroupingToggle() {
        groupingToggle.state = groupsFolded ? .on : .off
        groupingToggle.title = groupsFolded ? "Plié" : "Déplié"
    }
    func rebuildHistoryRows(matching: [Int]) {
        groupHeaders.removeAll(); groupControls.removeAll()
        let protected = Set((repository?.references.map(\.target) ?? []) + (repository?.worktrees.map(\.head) ?? []))
        historyGroups = HistoryGroup.make(commits, graph: graph, protected: protected)
        let groupIDs = Set(historyGroups.map(\.id))
        expandedGroups.formIntersection(groupIDs); collapsedGroups.formIntersection(groupIDs)
        updateGroupingToggle()
        guard search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            visibleIndices = matching; visibleGraph = matching.map { graph[$0] }; return
        }
        let folded = historyGroups.filter { isGroupFolded($0.id) }
        if folded.isEmpty {
            visibleIndices = matching; visibleGraph = matching.map { graph[$0] }
        } else {
            let projection = HistoryProjection.make(commits, groups: folded)
            visibleIndices = projection.indices; groupHeaders = projection.headers; visibleGraph = projection.graph
        }
        let groupsByID = Dictionary(uniqueKeysWithValues: historyGroups.map { ($0.id, $0) })
        for (row, index) in visibleIndices.enumerated() {
            if let group = groupsByID[commits[index].id] { groupControls[row] = group }
        }
    }
}
