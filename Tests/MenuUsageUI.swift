// Exercise the real menu targets and local storage without executing Git mutations.
func checkAdaptiveCommitMenu() {
    let suite = "GitGraphLite.MenuUsageChecks." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let controller = Controller(); controller.timer?.invalidate()
    controller.actionUsage = ActionUsage(defaults: defaults)
    // Obsolete pin preferences must not override the requested frequency order.
    defaults.set(["Drop Commit..."], forKey: "pinnedCommitActions")
    var invocations = 0
    func item(_ id: CommitActionID, context: String? = nil, enabled: Bool = true) -> NSMenuItem {
        let command = MenuCommand(id: id, context: context, usage: controller.actionUsage) { invocations += 1 }
        let item = NSMenuItem(title: id.title, action: #selector(MenuCommand.invoke(_:)), keyEquivalent: "")
        item.target = command; item.representedObject = command; item.isEnabled = enabled
        item.identifier = NSUserInterfaceItemIdentifier(id.rawValue)
        return item
    }
    func menu() -> NSMenu {
        let full = NSMenu(); full.autoenablesItems = false
        for id in CommitActionID.allCases where id != .copyBranchName { full.addItem(item(id)) }
        // Several refs for one action must take one ranked slot, not crowd out other actions.
        let branch = NSMenuItem(title: "Branches", action: nil, keyEquivalent: "")
        let choices = NSMenu(title: "Branches"); choices.autoenablesItems = false
        choices.addItem(item(.copyBranchName, context: "Branch: main"))
        choices.addItem(item(.copyBranchName, context: "Remote Branch: origin/main"))
        branch.submenu = choices; full.addItem(branch)
        return controller.compactCommitMenu(full)
    }
    func roots(_ menu: NSMenu) -> [String] { menu.items.compactMap { $0.identifier?.rawValue } }
    func find(_ id: CommitActionID, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.identifier?.rawValue == id.rawValue { return item }
            if let sub = item.submenu, let found = find(id, in: sub) { return found }
        }
        return nil
    }
    func click(_ id: CommitActionID, in menu: NSMenu) {
        let item = find(id, in: menu)!
        precondition(item.action != nil)
        precondition(NSApp.sendAction(item.action!, to: item.target, from: item))
    }
    let first = menu()
    precondition(roots(first) == ["checkout", "createWorktree", "compareHead", "copyHash", "copySubject"])
    precondition(CommitActionID.allCases.allSatisfy { controller.actionUsage.count($0) == 0 })
    click(.drop, in: first) // Actual invocation from Plus.
    precondition(invocations == 1 && controller.actionUsage.count(.drop) == 1)
    precondition(roots(menu()).first == "drop")
    let next = menu()
    click(.merge, in: next); click(.merge, in: next)
    precondition(Array(roots(menu()).prefix(2)) == ["merge", "drop"])
    let restored = ActionUsage(defaults: UserDefaults(suiteName: suite)!)
    precondition(restored.count(.merge) == 2 && restored.count(.drop) == 1)
    // Separate instances share this Mac's preferences, but a fresh local profile starts at zero.
    restored.record(.merge)
    precondition(controller.actionUsage.count(.merge) == 3)
    let emptySuite = suite + ".fresh"
    let emptyDefaults = UserDefaults(suiteName: emptySuite)!
    defer { emptyDefaults.removePersistentDomain(forName: emptySuite) }
    precondition(ActionUsage(defaults: emptyDefaults).count(.merge) == 0)
    let disabled = item(.reset, enabled: false)
    (disabled.representedObject as! MenuCommand).invoke(disabled)
    precondition(controller.actionUsage.count(.reset) == 0 && invocations == 3)
    let branchChoices = find(.copyBranchName, in: menu())!.submenu!
    let remote = branchChoices.items[1]
    precondition(remote.title == "Remote Branch: origin/main")
    precondition(NSApp.sendAction(remote.action!, to: remote.target, from: remote))
    precondition(controller.actionUsage.count(.copyBranchName) == 1)
    let promoted = menu()
    precondition(roots(promoted).count == 5)
    precondition(find(.copyBranchName, in: promoted)!.submenu!.items.count == 2)
    precondition(CommitActionID.allCases.allSatisfy { find($0, in: promoted) != nil })
    precondition(promoted.items.last!.title == "Plus…")
    controller.window?.close()
    print("PASS: five frequency-ranked actions, Plus promotion, stable ties, one count per invocation, local persistence, fresh-profile reset, disabled guards and explicit multi-ref targets")
}
checkAdaptiveCommitMenu()
