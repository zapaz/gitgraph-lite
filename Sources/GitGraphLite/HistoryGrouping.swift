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
        let state: NSControl.StateValue = groupsFolded ? .on : .off
        let title = groupsFolded ? "Plié" : "Déplié"
        if groupingToggle.state != state { groupingToggle.state = state }
        if groupingToggle.title != title { groupingToggle.title = title }
    }
    func rebuildHistoryRows(matching: [Int]) {
        groupHeaders.removeAll(); groupControls.removeAll()
        if historyGroupsDirty {
            let protected = Set((repository?.references.map(\.target) ?? []) + (repository?.worktrees.map(\.head) ?? []))
            historyGroups = HistoryGroup.make(commits, graph: graph, protected: protected)
            historyGroupsDirty = false; cachedHistoryProjection = nil
        }
        updateGroupingToggle()
        guard search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            visibleIndices = matching; visibleGraph = matching.map { graph[$0] }; return
        }
        let folded = historyGroups.filter { isGroupFolded($0.id) }
        if folded.isEmpty {
            visibleIndices = matching; visibleGraph = matching.map { graph[$0] }
        } else {
            let ids = Set(folded.map(\.id))
            let projection: HistoryProjection
            if let cachedHistoryProjection, cachedHistoryProjection.ids == ids { projection = cachedHistoryProjection.projection }
            else {
                projection = HistoryProjection.make(commits, groups: folded)
                cachedHistoryProjection = (ids, projection)
            }
            visibleIndices = projection.indices; groupHeaders = projection.headers; visibleGraph = projection.graph
        }
        let groupsByID = Dictionary(uniqueKeysWithValues: historyGroups.map { ($0.id, $0) })
        for (row, index) in visibleIndices.enumerated() {
            if let group = groupsByID[commits[index].id] { groupControls[row] = group }
        }
    }
    func reloadHistoryTable(previous: [Int], searching: Bool) {
        defer { historyRowsDirty = false; displayedSearchActive = searching }
        guard !historyRowsDirty, displayedSearchActive, searching else { table.reloadData(); return }
        // Search results retain their original commit order. Merge the two sorted
        // index lists to keep views for surviving commits instead of rebuilding them.
        var removed = IndexSet(), inserted = IndexSet(), old = 0, new = 0
        while old < previous.count || new < visibleIndices.count {
            if new == visibleIndices.count || (old < previous.count && previous[old] < visibleIndices[new]) {
                removed.insert(old); old += 1
            } else if old == previous.count || visibleIndices[new] < previous[old] {
                inserted.insert(new); new += 1
            } else { old += 1; new += 1 }
        }
        guard !removed.isEmpty || !inserted.isEmpty else { return }
        table.beginUpdates()
        table.removeRows(at: removed, withAnimation: [])
        table.insertRows(at: inserted, withAnimation: [])
        table.endUpdates()
    }

}
