import AppKit
import GitGraphCore

final class CallbackButton: NSButton {
    var callback: (() -> Void)?
    convenience init(_ title: String, _ callback: @escaping () -> Void) {
        self.init(title: title, target: nil, action: nil)
        self.callback = callback; target = self; action = #selector(invoke)
        bezelStyle = .rounded
    }
    @objc private func invoke() { callback?() }
}

private final class BranchList: NSStackView {
    override var isFlipped: Bool { true }
}
private final class BranchPickerBackground: NSView {
    override func draw(_ dirtyRect: NSRect) { NSColor.windowBackgroundColor.setFill(); dirtyRect.fill() }
}

final class BranchPicker: NSViewController, NSSearchFieldDelegate {
    weak var owner: Controller?
    let search = NSSearchField()
    let scroll = NSScrollView()
    let all = CallbackButton("All branches", {})
    override func loadView() {
        view = BranchPickerBackground(frame: NSRect(x: 0, y: 0, width: 620, height: 440))
        search.placeholderString = "Find a branch or worktree"; search.delegate = self
        all.setButtonType(.switch)
        all.callback = { [weak self] in
            guard let owner = self?.owner else { return }
            owner.branchSelection = owner.branchSelection == nil ? [] : nil
            owner.branchSelectionChanged()
        }
        let hint = NSTextField(wrappingLabelWithString: "Select several branches. Local + origin histories are combined. Pinned branches stay visible.")
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let stack = NSStackView(views: [search, all, hint, scroll]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14), stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 14), stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14)])
        for child in [search, hint, scroll] { child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        rebuild()
    }
    func controlTextDidChange(_ obj: Notification) { rebuild() }
    func rebuild() {
        guard isViewLoaded, let owner, let repo = owner.repository else { return }
        all.state = owner.branchSelection == nil ? .on : .off
        let query = search.stringValue.lowercased()
        let rows = BranchList(); rows.orientation = .vertical; rows.alignment = .leading; rows.spacing = 2
        let groups = repo.branchGroups.sorted {
            let a = $0.mandatoryPin || owner.branchPins.contains($0.name), b = $1.mandatoryPin || owner.branchPins.contains($1.name)
            return a != b ? a : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        for group in groups {
            let tree = repo.worktrees.first { $0.branch == "refs/heads/" + group.name }
            guard query.isEmpty || (group.name + " " + (tree?.path ?? "")).lowercased().contains(query) else { continue }
            let pinned = group.mandatoryPin || owner.branchPins.contains(group.name)
            let check = CallbackButton(group.name) { [weak owner] in
                guard let owner, !owner.operationRunning else { return }
                // A first click from All starts a focused selection rather than requiring deselecting every branch.
                if owner.branchSelection == nil { owner.branchSelection = [group.name] }
                else if owner.branchSelection!.contains(group.name) { owner.branchSelection!.remove(group.name) }
                else { owner.branchSelection!.insert(group.name) }
                owner.branchSelectionChanged()
            }
            check.setButtonType(.switch); check.state = owner.branchSelection == nil || pinned || owner.branchSelection!.contains(group.name) ? .on : .off
            check.isEnabled = !pinned && !owner.operationRunning
            check.font = .systemFont(ofSize: 12, weight: pinned ? .semibold : .regular)
            check.lineBreakMode = .byTruncatingMiddle
            check.toolTip = group.references.joined(separator: "\n")
            let versions = group.references.map { $0.hasPrefix("refs/heads/") ? "local" : $0.replacingOccurrences(of: "refs/remotes/", with: "") }.joined(separator: " · ")
            let detail = NSTextField(labelWithString: versions + (tree.map { "  |  " + $0.name + " · " + $0.stateLabel } ?? ""))
            detail.font = .systemFont(ofSize: 10); detail.textColor = .secondaryLabelColor; detail.lineBreakMode = .byTruncatingMiddle; detail.toolTip = tree?.path
            let name = NSStackView(views: [check, detail]); name.orientation = .vertical; name.alignment = .leading; name.spacing = 1
            let pin = CallbackButton(pinned ? "★" : "☆") { [weak owner] in
                guard let owner, !group.mandatoryPin else { return }
                if owner.branchPins.contains(group.name) { owner.branchPins.remove(group.name) } else { owner.branchPins.insert(group.name) }
                owner.saveBranchPins(); owner.branchSelectionChanged()
            }
            pin.isEnabled = !group.mandatoryPin && !owner.operationRunning
            pin.toolTip = group.mandatoryPin ? "Always pinned" : pinned ? "Unpin branch" : "Pin branch"
            pin.widthAnchor.constraint(equalToConstant: 30).isActive = true
            let worktree = CallbackButton(tree == nil ? "Create worktree" : "Open worktree") { [weak owner] in
                guard let owner, !owner.operationRunning else { return }
                owner.branchPopover.close()
                if let tree { owner.open(tree.path, focusHead: true) }
                else { owner.createAutomaticWorktree(branch: group.name) }
            }
            worktree.isEnabled = !owner.loading && !owner.operationRunning && (tree?.exists ?? true)
            worktree.toolTip = tree?.path ?? "Create and open a worktree automatically"
            worktree.widthAnchor.constraint(equalToConstant: 125).isActive = true
            let row = NSStackView(views: [name, pin, worktree]); row.spacing = 8; row.distribution = .fill
            row.heightAnchor.constraint(equalToConstant: 44).isActive = true
            name.setContentHuggingPriority(.init(1), for: .horizontal)
            name.setContentCompressionResistancePriority(.init(1), for: .horizontal)
            check.widthAnchor.constraint(equalTo: name.widthAnchor).isActive = true
            detail.widthAnchor.constraint(equalTo: name.widthAnchor).isActive = true
            rows.addArrangedSubview(row)
        }
        if rows.arrangedSubviews.isEmpty { rows.addArrangedSubview(NSTextField(labelWithString: "No matching branches")) }
        rows.frame = NSRect(x: 0, y: 0, width: 590, height: max(40, CGFloat(rows.arrangedSubviews.count)*46))
        for row in rows.arrangedSubviews { row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true }
        scroll.documentView = rows
        rows.translatesAutoresizingMaskIntoConstraints = false
        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            rows.topAnchor.constraint(equalTo: clip.topAnchor),
            rows.widthAnchor.constraint(equalTo: clip.widthAnchor),
            rows.heightAnchor.constraint(equalToConstant: max(40, CGFloat(rows.arrangedSubviews.count)*46))
        ])
    }
}

extension Controller {
    var branchPreferenceKey: String { "branchPins:" + (repository?.worktrees.first(where: \.isMain)?.path ?? repository?.path ?? "") }
    func saveBranchPins() { UserDefaults.standard.set(branchPins.sorted(), forKey: branchPreferenceKey) }
    @objc func showBranchPicker() {
        guard repository != nil, !operationRunning else { return }
        if branchPopover.isShown { branchPopover.close(); return }
        let picker = BranchPicker(); picker.owner = self
        branchPopover.contentViewController = picker; branchPopover.behavior = .transient
        branchPopover.show(relativeTo: branches.bounds, of: branches, preferredEdge: .maxY)
    }
    func branchSelectionChanged() {
        limit = 500; updateBranchButton(); (branchPopover.contentViewController as? BranchPicker)?.rebuild(); refreshNow()
    }
    func updateBranchButton() {
        guard let repo = repository else { return }
        let count = repo.branchGroups.filter { branchSelection?.contains($0.name) == true || $0.mandatoryPin || branchPins.contains($0.name) }.count
        branches.title = branchSelection == nil ? "All branches ▾" : "\(count) branches (including pins) ▾"
        branches.toolTip = branchSelection == nil ? "All local and remote histories" : repo.branchGroups.filter { branchSelection!.contains($0.name) || $0.mandatoryPin || branchPins.contains($0.name) }.map(\.name).joined(separator: ", ")
    }
}
