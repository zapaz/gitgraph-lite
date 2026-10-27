import AppKit
import GitGraphCore

extension Controller {
    @objc func groupingChanged(_ sender: NSButton) {
        let selected = table.selectedRowIndexes.compactMap { commit(at: $0)?.id }
        groupsFolded = sender.state == .on
        expandedGroups.removeAll()
        search.stringValue = ""
        UserDefaults.standard.set(groupsFolded, forKey: "groupCommits")
        applySearch(selected: selected)
    }
    func unfoldGroup(_ id: String) {
        guard groupsFolded, historyGroups.contains(where: { $0.id == id }), expandedGroups.insert(id).inserted else { return }
        let selected = table.selectedRowIndexes.compactMap { commit(at: $0)?.id }
        applySearch(selected: selected)
    }
    func updateGroupingToggle() {
        groupingToggle.state = groupsFolded ? .on : .off
        groupingToggle.title = groupsFolded ? "Plié" : "Déplié"
    }
    func rebuildHistoryRows(matching: [Int]) {
        groupHeaders.removeAll()
        let protected = Set((repository?.references.map(\.target) ?? []) + (repository?.worktrees.map(\.head) ?? []))
        historyGroups = HistoryGroup.make(commits, graph: graph, protected: protected)
        expandedGroups.formIntersection(Set(historyGroups.map(\.id)))
        updateGroupingToggle()
        guard groupsFolded, search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            visibleIndices = matching; visibleGraph = matching.map { graph[$0] }; return
        }
        let projection = HistoryProjection.make(commits, groups: historyGroups.filter { !expandedGroups.contains($0.id) })
        visibleIndices = projection.indices; groupHeaders = projection.headers; visibleGraph = projection.graph
    }
}
