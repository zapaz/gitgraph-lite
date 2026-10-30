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
        precondition(controller.groupingToggle.title == "Folded")
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
        precondition(foldedGraph.isFolded && foldedGraph.foldAction != nil, "A folded tail, including a root tail, exposes the plus control")
        precondition(controller.historyGroups == originalGroups)
        fold(false)
        let unfoldedCell = controller.tableView(controller.table, viewFor: column, row: 0) as! CommitCell
        precondition(unfoldedCell.foldSuffix.isEmpty, "The count disappears entirely when unfolded")
        let unfoldedGraph = controller.tableView(controller.table, viewFor: graphColumn, row: 0) as! GraphCell
        precondition(!unfoldedGraph.isFolded && unfoldedGraph.foldAction != nil, "The representative exposes a permanent minus when unfolded")
        selectInsideGroup(group.indices[2])
        fold(true)
        precondition(controller.visibleIndices.count == collapsedCount)
        precondition(controller.table.selectedRowIndexes.isEmpty, "Hidden interior selections are cleared")
    }
    controller.search.stringValue = "Change"
    controller.applySearch(selected: [])
    precondition(controller.groupHeaders.isEmpty && controller.groupControls.isEmpty)
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
    // The minus reverses an individual expansion without changing the global default.
    let expandedGraph = controller.tableView(controller.table, viewFor: graphColumn, row: 0) as! GraphCell
    precondition(!expandedGraph.isFolded && expandedGraph.foldAction != nil)
    precondition(expandedGraph.handleFoldClick(at: NSPoint(x: 16, y: expandedGraph.bounds.midY)))
    precondition(controller.isGroupFolded("a0") && !controller.isGroupFolded("b0"))
    precondition(controller.visibleIndices.map { controller.commits[$0].id } == ["a0", "b0", "b1", "b2", "root"])
    precondition(controller.groupsFolded && controller.groupingToggle.state == .on)
    fold(false); fold(true)
    precondition(controller.expandedGroups.isEmpty && controller.collapsedGroups.isEmpty && controller.groupHeaders.count == 2)
    // Route window-coordinate mouse events through the actual table and its managed cells.
    func clickInCell(_ cell: NSView, at point: NSPoint) {
        let location = cell.convert(point, to: nil)
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0, windowNumber: controller.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        precondition(controller.table.handleFoldClick(event), "The table must route the click to the plus/minus control or counter")
    }
    controller.table.layoutSubtreeIfNeeded()
    let graphIndex = controller.table.tableColumns.firstIndex { $0.identifier.rawValue == "graph" }!
    let managedGraph = controller.table.view(atColumn: graphIndex, row: 0, makeIfNecessary: true) as! GraphCell
    clickInCell(managedGraph, at: NSPoint(x: 16, y: managedGraph.bounds.midY))
    precondition(controller.expandedGroups == ["a0"] && controller.groupHeaders.count == 1)
    controller.table.layoutSubtreeIfNeeded()
    let managedMinus = controller.table.view(atColumn: graphIndex, row: 0, makeIfNecessary: true) as! GraphCell
    precondition(!managedMinus.isFolded && managedMinus.foldAction != nil)
    clickInCell(managedMinus, at: NSPoint(x: 16, y: managedMinus.bounds.midY))
    precondition(controller.expandedGroups.isEmpty && controller.groupHeaders.count == 2)
    fold(true); controller.table.layoutSubtreeIfNeeded()
    let subjectIndex = controller.table.tableColumns.firstIndex { $0.identifier.rawValue == "subject" }!
    let managedCount = controller.table.view(atColumn: subjectIndex, row: 0, makeIfNecessary: true) as! CommitCell
    let countImage = NSImage(size: managedCount.bounds.size); countImage.lockFocus(); managedCount.draw(managedCount.bounds); countImage.unlockFocus()
    clickInCell(managedCount, at: NSPoint(x: managedCount.foldCounterRect.midX, y: managedCount.foldCounterRect.midY))
    precondition(controller.expandedGroups == ["a0"] && controller.groupHeaders.count == 1)
    // Individual folding also works when the global setting is expanded.
    fold(false)
    precondition(controller.groupControls.count == 2 && controller.groupHeaders.isEmpty)
    let localMinus = controller.tableView(controller.table, viewFor: graphColumn, row: 0) as! GraphCell
    precondition(localMinus.handleFoldClick(at: NSPoint(x: 16, y: localMinus.bounds.midY)))
    precondition(!controller.groupsFolded && controller.groupingToggle.state == .off)
    precondition(controller.collapsedGroups == ["a0"] && controller.expandedGroups.isEmpty)
    precondition(controller.visibleIndices.map { controller.commits[$0].id } == ["a0", "b0", "b1", "b2", "root"])
    precondition(controller.footer.stringValue.contains("1 groupe replié (2 commits)"), "Footer includes individual folds even when the global default is expanded")
    // Repeating the same command must be idempotent, not toggle twice.
    controller.foldGroup("a0")
    precondition(controller.collapsedGroups == ["a0"] && controller.visibleIndices.count == 5)
    controller.search.stringValue = "Branch"
    controller.applySearch(selected: [])
    precondition(controller.groupHeaders.isEmpty && controller.groupControls.isEmpty)
    let searchGraph = controller.tableView(controller.table, viewFor: graphColumn, row: 0) as! GraphCell
    precondition(searchGraph.foldAction == nil && !searchGraph.handleFoldClick(at: NSPoint(x: 16, y: searchGraph.bounds.midY)))
    controller.search.stringValue = ""
    controller.applySearch(selected: [])
    precondition(controller.collapsedGroups == ["a0"] && controller.visibleIndices.count == 5)
    let localCount = controller.tableView(controller.table, viewFor: subjectColumn, row: 0) as! CommitCell
    localCount.frame = NSRect(x: 0, y: 0, width: 800, height: 24)
    let localImage = NSImage(size: localCount.bounds.size); localImage.lockFocus(); localCount.draw(localCount.bounds); localImage.unlockFocus()
    precondition(localCount.handleFoldClick(at: NSPoint(x: localCount.foldCounterRect.midX, y: localCount.foldCounterRect.midY)))
    precondition(controller.collapsedGroups.isEmpty && controller.visibleIndices.count == 7)
    controller.foldGroup("a0")
    let localPlus = controller.tableView(controller.table, viewFor: graphColumn, row: 0) as! GraphCell
    precondition(localPlus.isFolded && localPlus.handleFoldClick(at: NSPoint(x: 16, y: localPlus.bounds.midY)))
    controller.unfoldGroup("a0")
    precondition(controller.collapsedGroups.isEmpty && controller.visibleIndices.count == 7)
    controller.foldGroup("a0"); fold(false)
    precondition(controller.collapsedGroups.isEmpty && controller.visibleIndices.count == 7, "Changing the global setting clears local collapsed exceptions")
    let ordinary = controller.tableView(controller.table, viewFor: graphColumn, row: 2) as! GraphCell
    precondition(ordinary.foldAction == nil && !ordinary.handleFoldClick(at: NSPoint(x: 16, y: ordinary.bounds.midY)), "An interior commit must remain an ordinary selectable point")
    // A clipped graph control must not steal clicks from the description column.
    let narrowGraph = GraphCell(frame: NSRect(x: 0, y: 0, width: 55, height: 24))
    narrowGraph.row = GraphLayout.make((0..<4).map { Commit(id: "lane\($0)", parents: ["parent\($0)"]) }).last!
    precondition(narrowGraph.row!.lane == 3)
    var narrowClicks = 0
    narrowGraph.foldAction = { narrowClicks += 1 }
    precondition(!narrowGraph.handleFoldClick(at: NSPoint(x: 60, y: 12)), "A hit target outside GRAPH bounds must not intercept DESCRIPTION")
    precondition(!narrowGraph.handleFoldClick(at: NSPoint(x: 16, y: 12)))
    precondition(narrowClicks == 0)
    precondition(narrowGraph.handleFoldClick(at: NSPoint(x: 54, y: 12)), "The in-bounds portion of the target remains clickable")
    precondition(narrowClicks == 1)
    // Real merges and branch junctions survive both local fold directions.
    controller.commits.insert(Commit(id: "merge", parents: ["a0", "b0"], subject: "Merge B"), at: 0)
    controller.graph = GraphLayout.make(controller.commits)
    fold(false)
    controller.foldGroup("a0"); controller.foldGroup("b0")
    precondition(controller.visibleIndices.map { controller.commits[$0].id } == ["merge", "a0", "b0", "root"])
    precondition(controller.commit(at: 0)?.parents == ["a0", "b0"])
    precondition(controller.groupControls[0] == nil, "A merge must never become a fold control")
    let expectedGraph = GraphLayout.make([
        Commit(id: "merge", parents: ["a0", "b0"]), Commit(id: "a0", parents: ["root"]),
        Commit(id: "b0", parents: ["root"]), Commit(id: "root", parents: [])
    ])
    func graphSignature(_ rows: [GraphRow]) -> [String] {
        rows.map { row in "\(row.lane):\(row.color):" + row.edges.map { "\($0.from)>\($0.to):\($0.color):\($0.segment)" }.joined(separator: ",") }
    }
    precondition(graphSignature(controller.visibleGraph) == graphSignature(expectedGraph), "Contraction must retain both merge-parent paths and the shared root")
    controller.unfoldGroup("a0"); controller.unfoldGroup("b0")
    precondition(controller.visibleIndices.count == controller.commits.count)
    precondition(graphSignature(controller.visibleGraph) == graphSignature(controller.graph))
    controller.commits = [Commit(id: "one", parents: ["last"]), Commit(id: "last", parents: [])]
    controller.graph = GraphLayout.make(controller.commits); fold(true)
    precondition(controller.historyGroups.isEmpty && controller.groupControls.isEmpty && controller.visibleIndices.count == 2)
    let single = controller.tableView(controller.table, viewFor: graphColumn, row: 0) as! GraphCell
    precondition(single.foldAction == nil && !single.handleFoldClick(at: NSPoint(x: 16, y: single.bounds.midY)))
    controller.window?.close()
    print("PASS: permanent plus/minus and counters fold both ways under either global default; merges, terminal commits, search, selection and single-commit exclusions stay correct")
}
checkGroupingControls()

func checkHistoryCacheInvalidation() {
    _ = NSApplication.shared
    let controller = Controller(); controller.timer?.invalidate(); controller.groupsFolded = true
    func install(_ prefix: String) {
        controller.commits = (0..<8).map { Commit(id: "\(prefix)\($0)", parents: $0 == 7 ? [] : ["\(prefix)\($0+1)"], author: "Élodie", subject: "\(prefix) change \($0)") }
        controller.graph = GraphLayout.make(controller.commits)
        controller.search.stringValue = ""; controller.applySearch(selected: [])
    }
    install("alpha")
    precondition(controller.visibleIndices.count == 1)
    controller.search.stringValue = "ALPHA"; controller.applySearch(selected: [])
    precondition(controller.visibleIndices.count == 8)
    controller.search.stringValue = ""; controller.applySearch(selected: [])
    precondition(controller.groupHeaders[0]?.id == "alpha0" && controller.visibleIndices.count == 1)
    install("beta")
    controller.search.stringValue = "alpha"; controller.applySearch(selected: [])
    precondition(controller.visibleIndices.isEmpty, "A same-sized history replacement must invalidate its search index")
    controller.search.stringValue = "BETA"; controller.applySearch(selected: [])
    precondition(controller.visibleIndices.count == 8)
    controller.search.stringValue = "beta change 1"; controller.applySearch(selected: ["beta1"])
    precondition(controller.table.numberOfRows == 1 && controller.commit(at: 0)?.id == "beta1")
    precondition(controller.table.selectedRowIndexes == IndexSet(integer: 0))
    controller.search.stringValue = "beta change"; controller.applySearch(selected: ["beta1"])
    precondition(controller.table.numberOfRows == 8 && controller.table.selectedRowIndexes == IndexSet(integer: 1))
    controller.search.stringValue = ""; controller.applySearch(selected: [])
    precondition(controller.groupHeaders[0]?.id == "beta0", "A cached folded graph must never retain the previous history")
    controller.unfoldGroup("beta0")
    precondition(controller.visibleIndices.count == 8)
    controller.foldGroup("beta0")
    precondition(controller.visibleIndices.count == 1 && controller.commit(at: 0)?.id == "beta0")
    // Once empty, filtering does not invalidate/rebuild the four detail tables again.
    controller.clearDetails(); let emptyDetailID = controller.detailID
    controller.search.stringValue = "missing"; controller.applySearch(selected: [])
    controller.search.stringValue = "still missing"; controller.applySearch(selected: [])
    precondition(controller.detailID == emptyDetailID)
    // A real pending/visible selection is still cleared and its callback invalidated.
    controller.target = "beta0"; let pendingID = controller.detailID
    controller.clearDetails()
    precondition(controller.target == nil && controller.detailID != pendingID)
    controller.window?.close()
    print("PASS: search/group/projection caches invalidate after replacing history; folding, search restoration and detail cancellation remain correct")
}
checkHistoryCacheInvalidation()
