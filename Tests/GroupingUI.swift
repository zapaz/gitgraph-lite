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
        precondition(foldedGraph.isFolded, "A folded tail, including a root tail, gets the three-line marker")
        precondition(controller.historyGroups == originalGroups)
        fold(false)
        let unfoldedCell = controller.tableView(controller.table, viewFor: column, row: 0) as! CommitCell
        precondition(unfoldedCell.foldSuffix.isEmpty, "The count disappears entirely when unfolded")
        let unfoldedGraph = controller.tableView(controller.table, viewFor: graphColumn, row: 0) as! GraphCell
        precondition(!unfoldedGraph.isFolded, "The marker disappears when unfolded")
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
    // Opening one interleaved branch must not unfold its neighbour.
    controller.commits = [
        Commit(id: "a0", parents: ["a1"], subject: "Branch A"), Commit(id: "b0", parents: ["b1"], subject: "Branch B"),
        Commit(id: "a1", parents: ["a2"]), Commit(id: "b1", parents: ["b2"]),
        Commit(id: "a2", parents: ["root"]), Commit(id: "b2", parents: ["root"]), Commit(id: "root", parents: [])
    ]
    controller.graph = GraphLayout.make(controller.commits)
    fold(true)
    precondition(controller.groupHeaders.count == 2)
    let graphColumn = controller.table.tableColumns.first { $0.identifier.rawValue == "graph" }!
    let graphCell = controller.tableView(controller.table, viewFor: graphColumn, row: 0) as! GraphCell
    precondition(!graphCell.handleFoldClick(at: NSPoint(x: 80, y: 12)))
    precondition(graphCell.handleFoldClick(at: NSPoint(x: 16, y: graphCell.bounds.midY)))
    precondition(controller.expandedGroups == ["a0"])
    precondition(controller.groupHeaders.count == 1 && controller.groupHeaders.values.first!.id == "b0")
    precondition(controller.groupsFolded && controller.groupingToggle.state == .on)
    let bRow = controller.visibleIndices.firstIndex { controller.commits[$0].id == "b0" }!
    let subjectColumn = controller.table.tableColumns.first { $0.identifier.rawValue == "subject" }!
    let countCell = controller.tableView(controller.table, viewFor: subjectColumn, row: bRow) as! CommitCell
    countCell.frame = NSRect(x: 0, y: 0, width: 800, height: 24)
    let image = NSImage(size: countCell.bounds.size); image.lockFocus(); countCell.draw(countCell.bounds); image.unlockFocus()
    precondition(!countCell.foldCounterRect.isEmpty)
    precondition(!countCell.handleFoldClick(at: .zero))
    precondition(countCell.handleFoldClick(at: NSPoint(x: countCell.foldCounterRect.midX, y: countCell.foldCounterRect.midY)))
    precondition(controller.groupHeaders.isEmpty && controller.visibleIndices.count == 7)
    fold(false); fold(true)
    precondition(controller.expandedGroups.isEmpty && controller.groupHeaders.count == 2)
    // Route window-coordinate mouse events through the actual table and its managed cells.
    func clickInCell(_ cell: NSView, at point: NSPoint) {
        let location = cell.convert(point, to: nil)
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0, windowNumber: controller.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        precondition(controller.table.handleFoldClick(event), "The table must route the click to the folded marker/counter")
    }
    controller.table.layoutSubtreeIfNeeded()
    let graphIndex = controller.table.tableColumns.firstIndex { $0.identifier.rawValue == "graph" }!
    let managedGraph = controller.table.view(atColumn: graphIndex, row: 0, makeIfNecessary: true) as! GraphCell
    clickInCell(managedGraph, at: NSPoint(x: 16, y: managedGraph.bounds.midY))
    precondition(controller.expandedGroups == ["a0"] && controller.groupHeaders.count == 1)
    fold(true); controller.table.layoutSubtreeIfNeeded()
    let subjectIndex = controller.table.tableColumns.firstIndex { $0.identifier.rawValue == "subject" }!
    let managedCount = controller.table.view(atColumn: subjectIndex, row: 0, makeIfNecessary: true) as! CommitCell
    let countImage = NSImage(size: managedCount.bounds.size); countImage.lockFocus(); managedCount.draw(managedCount.bounds); countImage.unlockFocus()
    clickInCell(managedCount, at: NSPoint(x: managedCount.foldCounterRect.midX, y: managedCount.foldCounterRect.midY))
    precondition(controller.expandedGroups == ["a0"] && controller.groupHeaders.count == 1)
    controller.commits = [Commit(id: "one", parents: ["last"]), Commit(id: "last", parents: [])]
    controller.graph = GraphLayout.make(controller.commits); fold(true)
    precondition(controller.historyGroups.isEmpty && controller.visibleIndices.count == 2)
    controller.window?.close()
    print("PASS: three-line and counter click targets unfold one chain only, global reset restores folding, and single hidden commits stay visible")
}
checkGroupingControls()
