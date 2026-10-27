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
        let row = controller.visibleIndices.indices.first { controller.groupHeaders[$0] == nil && controller.visibleIndices[$0] == index }!
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
        precondition(controller.table.selectedRowIndexes.isEmpty, "Hidden selections must not select group headers")
        precondition(controller.historyGroups == originalGroups)
        precondition(controller.groupView(group) is NSTextField, "Folded summaries must be labels, not per-group buttons")
        fold(false)
        selectInsideGroup(group.indices[2])
        fold(true)
        precondition(controller.visibleIndices.count == collapsedCount)
    }
    controller.search.stringValue = "Change"
    controller.applySearch(selected: [])
    precondition(controller.groupHeaders.isEmpty)
    controller.search.stringValue = ""
    controller.applySearch(selected: [])
    precondition(controller.visibleIndices.count == collapsedCount)
    controller.window?.close()
    print("PASS: global-only fold checkbox, exact commit rows without unfolded headers, noninteractive folded summaries, stable selection and search restoration")
}
checkGroupingControls()
