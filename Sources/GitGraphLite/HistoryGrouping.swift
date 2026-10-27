import AppKit
import GitGraphCore

extension Controller {
    @objc func groupingChanged(_ sender: NSButton) {
        let selected = table.selectedRowIndexes.compactMap { commit(at: $0)?.id }
        groupsFolded = sender.state == .on
        search.stringValue = ""
        UserDefaults.standard.set(groupsFolded, forKey: "groupCommits")
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
        updateGroupingToggle()
        guard groupsFolded, search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            visibleIndices = matching; visibleGraph = matching.map { graph[$0] }; return
        }
        let projection = HistoryProjection.make(commits, groups: historyGroups)
        visibleIndices = projection.indices; groupHeaders = projection.headers; visibleGraph = projection.graph
    }
}
