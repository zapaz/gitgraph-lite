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
    controller.groupingEnabled = true
    controller.applySearch(selected: [])
    let group = controller.historyGroups[0]
    let collapsedCount = controller.visibleIndices.count
    let originalGroups = controller.historyGroups
    func command(_ tag: Int) {
        let item = controller.groupingPicker.itemArray.dropFirst().first { $0.tag == tag }!
        precondition(NSApp.sendAction(item.action!, to: item.target, from: item))
    }
    func selectInsideGroup(_ index: Int) {
        let id = controller.commits[index].id
        controller.applySearch(selected: [id])
        precondition(controller.historyGroups == originalGroups, "Selection must not change group IDs or boundaries")
        let row = controller.visibleIndices.indices.first { controller.groupHeaders[$0] == nil && controller.visibleIndices[$0] == index }!
        precondition(controller.table.selectedRowIndexes.contains(row))
    }
    for _ in 0..<2 {
        command(2)
        precondition(controller.visibleIndices.count == controller.commits.count + originalGroups.count)
        selectInsideGroup(group.indices.lowerBound) // Previously selected a synthetic header too.
        command(1)
        precondition(controller.visibleIndices.count == collapsedCount)
        precondition(controller.table.selectedRowIndexes.isEmpty, "Hidden selections must not select group headers")
        let button = controller.groupView(group) as! CallbackButton
        button.callback?()
        precondition(controller.visibleIndices.count == collapsedCount + group.indices.count)
        selectInsideGroup(group.indices.lowerBound+2)
        (controller.groupView(group) as! CallbackButton).callback?()
        precondition(controller.visibleIndices.count == collapsedCount, "A group must collapse after selecting an interior commit")
        precondition(controller.historyGroups == originalGroups)
    }
    command(0)
    precondition(controller.visibleIndices.count == controller.commits.count)
    command(1)
    precondition(controller.visibleIndices.count == collapsedCount)
    controller.search.stringValue = "Change"
    controller.applySearch(selected: [])
    precondition(controller.groupHeaders.isEmpty)
    controller.search.stringValue = ""
    controller.applySearch(selected: [])
    precondition(controller.visibleIndices.count == collapsedCount)
    controller.window?.close()
    print("PASS: real AppKit grouping commands, repeated global collapse, individual collapse after commit selection, stable IDs, hidden selections and search restoration")
}
checkGroupingControls()
