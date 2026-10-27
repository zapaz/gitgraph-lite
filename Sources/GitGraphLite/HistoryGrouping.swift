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
    func groupView(_ group: HistoryGroup) -> NSView {
        let first = commits[group.indices[0]], last = commits[group.indices.last!]
        let label = NSTextField(labelWithString: "\(group.indices.count) commits repliés  ·  \(first.subject) …")
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .controlAccentColor; label.lineBreakMode = .byTruncatingTail
        label.toolTip = "\(first.id.prefix(8)) … \(last.id.prefix(8))\nDécochez Plié pour afficher tous les commits."
        return label
    }
}
