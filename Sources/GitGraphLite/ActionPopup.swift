import AppKit
import GitGraphCore

/// One sheet carries an action from start to finish: optional input, progress, then success or error.
/// Success closes itself after three seconds; an error stays until the user closes it. The cross (or Escape) is the only close control.
/// Every value shown (hash, name, path, Git output, error text) has its own copy button.
final class ActionPopup: NSObject {
    struct Fact { let label: String; let value: String }
    enum Phase { case input, running, success, failure }

    static let successDelay: TimeInterval = 3
    let panel: NSPanel
    private(set) var phase = Phase.input
    private weak var parent: NSWindow?
    private let titleField = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private let spinner = NSProgressIndicator()
    private let detailField = NSTextField(wrappingLabelWithString: "")
    private let inputs = NSStackView()
    private let facts = NSStackView()
    private let message = NSStackView()
    private let buttons = NSStackView()
    private let closeCross = CallbackButton("") {}
    private var dismissal: DispatchWorkItem?
    private var keepAlive: ActionPopup?
    /// Fields that must not be empty: the confirm button stays greyed out until each has text.
    private let required: [NSTextField]
    private weak var confirmButton: NSButton?
    private var confirmArmed = false
    var copy: (String) -> Void = { text in NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }

    init(title: String, detail: String = "", facts initial: [Fact] = [], controls: [NSView] = [], required: [NSTextField] = [], parent: NSWindow?) {
        self.required = required
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 100), styleMask: [.titled, .docModalWindow], backing: .buffered, defer: true)
        self.parent = parent
        super.init()
        titleField.stringValue = title; titleField.font = .systemFont(ofSize: 13, weight: .semibold)
        titleField.lineBreakMode = .byTruncatingMiddle
        detailField.stringValue = detail; detailField.isHidden = detail.isEmpty
        detailField.font = .systemFont(ofSize: 12); detailField.textColor = .secondaryLabelColor
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 18).isActive = true; icon.heightAnchor.constraint(equalToConstant: 18).isActive = true
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        closeCross.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        closeCross.isBordered = false; closeCross.toolTip = "Close"; closeCross.contentTintColor = .secondaryLabelColor
        closeCross.callback = { [weak self] in self?.close() }
        closeCross.keyEquivalent = "\u{1b}"
        let headerSpacer = NSView(); headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [icon, spinner, titleField, headerSpacer, closeCross]); header.spacing = 8
        for stack in [inputs, facts, message] { stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6 }
        inputs.spacing = 10
        controls.forEach { inputs.addArrangedSubview($0); $0.widthAnchor.constraint(equalTo: inputs.widthAnchor).isActive = true }
        inputs.isHidden = controls.isEmpty
        setFacts(initial)
        buttons.spacing = 8
        let content = NSStackView(views: [header, detailField, facts, inputs, message, buttons])
        content.orientation = .vertical; content.alignment = .leading; content.spacing = 12
        content.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 16, right: 20)
        content.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = NSView(); panel.contentView!.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
            content.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
            content.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor),
            content.widthAnchor.constraint(equalToConstant: 320)
        ])
        for view in [header, detailField, facts, inputs, message, buttons] { view.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -40).isActive = true }
        setAccessibility()
        for field in required {
            NotificationCenter.default.addObserver(self, selector: #selector(inputChanged), name: NSControl.textDidChangeNotification, object: field)
        }
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    var canConfirm: Bool { required.allSatisfy { !$0.stringValue.trimmingCharacters(in: .whitespaces).isEmpty } }
    @objc private func inputChanged() { confirmButton?.isEnabled = confirmArmed && canConfirm }
    private func setAccessibility() {
        panel.setAccessibilityLabel(titleField.stringValue)
    }

    // MARK: Phases

    /// Shows the input fields; `confirm` runs when the user presses the main button.
    func askInput(confirm title: String, focus: NSView? = nil, action: @escaping () -> Void) {
        phase = .input; closeCross.isHidden = false
        icon.isHidden = true; spinner.stopAnimation(nil); inputs.isHidden = inputs.arrangedSubviews.isEmpty
        setMessage(nil)
        // The cross (or Escape) closes; no separate Cancel button.
        // The Return that chose the menu item must not also confirm: the button arms itself after a short delay.
        confirmArmed = false
        let button = setButtons([(title, { [weak self] in if self?.canConfirm == true { action() } })]).first
        button?.isEnabled = false; confirmButton = button
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.phase == .input else { return }
            self.confirmArmed = true; self.confirmButton?.isEnabled = self.canConfirm
        }
        present()
        if let focus { panel.makeFirstResponder(focus); (focus as? NSTextField)?.currentEditor()?.selectAll(nil) }
    }
    func showRunning(_ text: String) {
        phase = .running
        icon.isHidden = true; spinner.startAnimation(nil); inputs.isHidden = true; closeCross.isHidden = true
        setMessage(text, copyable: false)
        setButtons([])
        present()
    }
    func showSuccess(_ text: String, facts newFacts: [Fact]? = nil, output: String = "") {
        phase = .success; closeCross.isHidden = false
        spinner.stopAnimation(nil); inputs.isHidden = true
        setIcon("checkmark.circle.fill", colors: [.white, .systemGreen])
        if let newFacts { setFacts(newFacts) }
        setMessage(output.isEmpty ? text : text + "\n\n" + output, copyable: !output.isEmpty)
        setButtons([])
        present()
        let work = DispatchWorkItem { [weak self] in self?.close() }
        dismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.successDelay, execute: work)
    }
    /// An error stays on screen. When the action had inputs, Back returns to them with the typed values kept.
    /// `actions` replace Back with recovery buttons, such as Abort and Continue after a conflict.
    /// `details` (such as Git's full output) is not shown but is what the copy button copies.
    func showFailure(_ text: String, details: String? = nil, back: (() -> Void)? = nil, actions: [(String, () -> Void)] = []) {
        phase = .failure; closeCross.isHidden = false
        spinner.stopAnimation(nil); inputs.isHidden = true
        setIcon("exclamationmark.triangle.fill", colors: [.black, .systemYellow])
        setMessage(text, copyable: true, copyValue: details)
        setButtons(!actions.isEmpty ? actions : back.map { [("Back", $0)] } ?? [])
        present()
    }
    func close() {
        dismissal?.cancel(); dismissal = nil
        if let sheetParent = panel.sheetParent { sheetParent.endSheet(panel) } else { panel.orderOut(nil) }
        keepAlive = nil
    }

    // MARK: Building blocks

    private func present() {
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.setContentSize(panel.contentView!.fittingSize)
        guard panel.sheetParent == nil, !panel.isVisible else { return }
        keepAlive = self
        if let parent { parent.beginSheet(panel) } else { panel.center(); panel.makeKeyAndOrderFront(nil) }
    }
    private func setIcon(_ name: String, colors: [NSColor]) {
        icon.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(paletteColors: colors))
        icon.isHidden = false
    }
    func setFacts(_ list: [Fact]) {
        facts.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for fact in list {
            let label = NSTextField(labelWithString: fact.label)
            label.font = .systemFont(ofSize: 11); label.textColor = .secondaryLabelColor
            label.widthAnchor.constraint(equalToConstant: 64).isActive = true
            let value = NSTextField(labelWithString: fact.value)
            value.font = .monospacedSystemFont(ofSize: 11, weight: .regular); value.isSelectable = true
            value.lineBreakMode = .byTruncatingMiddle
            value.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let row = NSStackView(views: [label, value, copyButton(fact.value, name: fact.label)]); row.spacing = 6
            facts.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: facts.widthAnchor).isActive = true
        }
        facts.isHidden = list.isEmpty
    }
    private func setMessage(_ text: String?, copyable: Bool = false, copyValue: String? = nil) {
        message.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let text, !text.isEmpty else { message.isHidden = true; return }
        let field = NSTextField(wrappingLabelWithString: String(text.prefix(3000)))
        field.font = .systemFont(ofSize: 12); field.isSelectable = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: copyable ? [field, copyButton(copyValue ?? text, name: "message")] : [field]); row.alignment = .top; row.spacing = 6
        message.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: message.widthAnchor).isActive = true
        message.isHidden = false
    }
    private func copyButton(_ value: String, name: String) -> NSButton {
        let button = CallbackButton("") {}
        button.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy " + name)
        button.isBordered = false; button.toolTip = "Copy " + name
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.callback = { [weak self, weak button] in
            self?.copy(value)
            button?.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { button?.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy " + name) }
        }
        return button
    }
    /// Lays out the bottom-right buttons; the last one is the default (Return).
    @discardableResult private func setButtons(_ list: [(String, () -> Void)]) -> [NSButton] {
        buttons.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        buttons.addArrangedSubview(spacer)
        let made = list.enumerated().map { index, entry -> NSButton in
            let button = CallbackButton(entry.0, entry.1)
            if index == list.count-1 { button.keyEquivalent = "\r" }
            buttons.addArrangedSubview(button); return button
        }
        buttons.isHidden = list.isEmpty
        return made
    }
}

typealias PopupWork = () throws -> (message: String, facts: [ActionPopup.Fact]?, output: String)
/// A second way to finish when the first one fails with a matching error, such as Delete Anyway.
struct PopupFallback { let title: String; let when: (String) -> Bool; let work: PopupWork }

extension Controller {
    /// Runs `work` behind a popup. With `confirm`, the popup first asks for input; without, it runs at once.
    /// Git work runs off the main thread and refreshes the graph; quick local work (a copy) stays on the main thread.
    @discardableResult func actionPopup(_ title: String, detail: String = "", facts: [ActionPopup.Fact] = [], controls: [NSView] = [], required: [NSTextField] = [], confirm: String? = nil, focus: NSView? = nil, running: String? = nil, git repo: Repository? = nil, fallback: PopupFallback? = nil, then: (() -> Void)? = nil, work: @escaping PopupWork) -> ActionPopup {
        let popup = ActionPopup(title: title, detail: detail, facts: facts, controls: controls, required: required, parent: window)
        popup.copy = { [weak self] in self?.copyText($0) }
        var back: (() -> Void)?
        let start = { [weak self, weak popup] in
            guard let self, let popup else { return }
            self.runPopupWork(popup, running: running ?? title, repo: repo, back: back, fallback: fallback, then: then, work: work)
        }
        if let confirm {
            back = { [weak popup] in popup?.askInput(confirm: confirm, focus: focus, action: start) }
            popup.askInput(confirm: confirm, focus: focus, action: start)
        } else { start() }
        return popup
    }
    private func runPopupWork(_ popup: ActionPopup, running: String, repo: Repository?, back: (() -> Void)?, fallback: PopupFallback? = nil, then: (() -> Void)? = nil, work: @escaping PopupWork) {
        guard let repo else {
            switch Result(catching: work) {
            case .success(let done): popup.showSuccess(done.message, facts: done.facts, output: done.output)
            case .failure(let error): popup.showFailure(error.localizedDescription, back: back)
            }
            return
        }
        guard !operationRunning, repository?.path == repo.path else {
            popup.showFailure("Another Git action is still running. Wait for it to finish, then try again.", back: back); return
        }
        operationRunning = true; spinner.startAnimation(nil); branches.isEnabled = false; more.isEnabled = false
        footer.stringValue = running + "…"
        popup.showRunning(running + "…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result(catching: work)
            // A cherry-pick, merge or revert that stops on conflicts leaves an operation to finish or undo.
            let pending: String? = { if case .failure = result { return (try? Git.pendingOperation(at: repo.path)) ?? nil }; return nil }()
            DispatchQueue.main.async {
                guard let self else { return }
                self.operationRunning = false; self.spinner.stopAnimation(nil); self.branches.isEnabled = true; self.more.isEnabled = true
                // A deleted displayed worktree has no folder left to refresh; `then` moves the window away.
                if FileManager.default.fileExists(atPath: repo.path) { self.refresh(path: repo.path) }
                switch result {
                case .success(let done): popup.showSuccess(done.message, facts: done.facts, output: done.output); then?()
                case .failure(let error):
                    let text = error.localizedDescription
                    if let pending { self.showConflict(popup, operation: pending, repo: repo, error: text) }
                    else if let fallback, fallback.when(text) {
                        popup.showFailure(text, actions: [(fallback.title, { [weak self, weak popup] in
                            guard let self, let popup else { return }
                            self.runPopupWork(popup, running: fallback.title, repo: repo, back: nil, work: fallback.work)
                        })])
                    }
                    else { popup.showFailure(text, back: back) }
                }
            }
        }
    }
    /// Offers the two ways out of a stopped operation in the same popup.
    func showConflict(_ popup: ActionPopup, operation: String, repo: Repository, error: String) {
        let name = operation.prefix(1).uppercased() + operation.dropFirst()
        let text = "\(name) stopped on conflicts. Fix and stage the files, then Continue, or Abort."
        let recover = { [weak self, weak popup] (abort: Bool) in
            guard let self, let popup else { return }
            self.runPopupWork(popup, running: abort ? "Aborting \(operation)" : "Continuing \(operation)", repo: repo, back: nil) {
                let result = try Git.perform(abort ? .abortOperation(operation) : .continueOperation(operation), at: repo.path)
                return (abort ? "\(name) aborted." : "\(name) finished.", nil, result.output)
            }
        }
        popup.showFailure(text, details: error, actions: [("Abort", { recover(true) }), ("Continue", { recover(false) })])
    }
}
