// AppKit regression checks compiled with the real Controller by check-grouping-ui.sh.
func checkGroupingControls() {
    let previous = UserDefaults.standard.object(forKey: "groupCommits")
    defer {
        if let previous { UserDefaults.standard.set(previous, forKey: "groupCommits") }
        else { UserDefaults.standard.removeObject(forKey: "groupCommits") }
    }
    _ = NSApplication.shared
    let controller = Controller()
    controller.timer?.invalidate()
    controller.commits = (0..<55).map { Commit(id: "commit\($0)", parents: $0 == 54 ? [] : ["commit\($0+1)"], subject: "Change \($0)") }
    controller.graph = GraphLayout.make(controller.commits)
    controller.groupsFolded = true
    controller.applySearch(selected: [])
    let group = controller.historyGroups[0]
    let collapsedCount = controller.visibleIndices.count
    let originalGroups = controller.historyGroups
    func fold(_ folded: Bool) {
        controller.groupingToggle.state = folded ? .on : .off
        precondition(NSApp.sendAction(controller.groupingToggle.action!, to: controller.groupingToggle.target, from: controller.groupingToggle))
        precondition(controller.groupingToggle.title == (folded ? "Plié" : "Déplié"))
    }
    func selectInsideGroup(_ index: Int) {
        let id = controller.commits[index].id
        controller.applySearch(selected: [id])
        precondition(controller.historyGroups == originalGroups, "Selection must not change group IDs or boundaries")
        let row = controller.visibleIndices.indices.first { controller.visibleIndices[$0] == index }!
        precondition(controller.table.selectedRowIndexes.contains(row))
    }
    for _ in 0..<2 {
        fold(false)
        precondition(controller.visibleIndices == Array(controller.commits.indices))
        precondition(controller.groupHeaders.isEmpty, "Unfolded history must have no synthetic headers")
        precondition(controller.visibleGraph.count == controller.commits.count)
        selectInsideGroup(group.indices[0])
        fold(true)
        precondition(controller.visibleIndices.count == collapsedCount)
        precondition(controller.table.selectedRowIndexes == IndexSet(integer: 0), "The retained newest commit stays selected")
        precondition(controller.commit(at: 0)?.id == controller.commits[0].id)
        precondition(controller.tableView(controller.table, shouldSelectRow: 0))
        let column = controller.table.tableColumns.first { $0.identifier.rawValue == "subject" }!
        let cell = controller.tableView(controller.table, viewFor: column, row: 0) as! CommitCell
        precondition(cell.foldSuffix == " (54 commits pliés)")
        let graphColumn = controller.table.tableColumns.first { $0.identifier.rawValue == "graph" }!
        let foldedGraph = controller.tableView(controller.table, viewFor: graphColumn, row: 0) as! GraphCell
        precondition(foldedGraph.isFolded, "A folded tail, including a root tail, gets a zigzag")
        precondition(controller.historyGroups == originalGroups)
        fold(false)
        let unfoldedCell = controller.tableView(controller.table, viewFor: column, row: 0) as! CommitCell
        precondition(unfoldedCell.foldSuffix.isEmpty, "The count disappears entirely when unfolded")
        let unfoldedGraph = controller.tableView(controller.table, viewFor: graphColumn, row: 0) as! GraphCell
        precondition(!unfoldedGraph.isFolded, "The zigzag disappears when unfolded")
        selectInsideGroup(group.indices[2])
        fold(true)
        precondition(controller.visibleIndices.count == collapsedCount)
        precondition(controller.table.selectedRowIndexes.isEmpty, "Hidden interior selections are cleared")
    }
    controller.search.stringValue = "Change"
    controller.applySearch(selected: [])
    precondition(controller.groupHeaders.isEmpty)
    controller.search.stringValue = ""
    controller.applySearch(selected: [])
    precondition(controller.visibleIndices.count == collapsedCount)
    controller.window?.close()
    print("PASS: global folding keeps the newest real commit, includes the root, appends the exact hidden count, and removes all fold annotations when unfolded")
}
checkGroupingControls()
