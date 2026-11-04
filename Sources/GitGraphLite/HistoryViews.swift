import AppKit
import GitGraphCore

// The graph and branch labels share this high-contrast palette.
let palette: [NSColor] = [
    NSColor(srgbRed: 0.00, green: 0.48, blue: 0.96, alpha: 1),
    NSColor(srgbRed: 0.86, green: 0.00, blue: 0.60, alpha: 1),
    NSColor(srgbRed: 0.00, green: 0.70, blue: 0.16, alpha: 1),
    NSColor(srgbRed: 0.91, green: 0.47, blue: 0.00, alpha: 1),
    NSColor(srgbRed: 0.57, green: 0.18, blue: 0.94, alpha: 1),
    NSColor(srgbRed: 0.91, green: 0.14, blue: 0.20, alpha: 1),
    NSColor(srgbRed: 0.00, green: 0.66, blue: 0.69, alpha: 1)
]

final class GraphCell: NSView {
    var row: GraphRow?
    var filtered = false
    var isHead = false
    var isFolded = false
    var foldAction: (() -> Void)? {
        didSet {
            let enabled = foldAction != nil && !filtered
            let lane = enabled ? row?.lane : nil
            guard enabled != foldControlEnabled || lane != foldCursorLane else { return }
            foldControlEnabled = enabled; foldCursorLane = lane
            setAccessibilityElement(enabled)
            if enabled { setAccessibilityRole(.button) }
            window?.invalidateCursorRects(for: self)
        }
    }
    private var foldControlEnabled = false
    private var foldCursorLane: Int?
    override var isFlipped: Bool { true }
    private var foldTarget: NSRect {
        guard let row else { return .zero }
        return NSRect(x: 16 + CGFloat(row.lane)*15-10, y: bounds.midY-10, width: 20, height: 20)
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        if !filtered, foldAction != nil { addCursorRect(foldTarget.intersection(bounds), cursor: .pointingHand) }
    }
    override func accessibilityPerformPress() -> Bool {
        guard !filtered, let foldAction else { return false }
        foldAction(); return true
    }
    @discardableResult func handleFoldClick(at point: NSPoint) -> Bool {
        guard !filtered, row != nil, let foldAction, bounds.contains(point), foldTarget.contains(point) else { return false }
        foldAction(); return true
    }
    override func mouseDown(with event: NSEvent) {
        if !handleFoldClick(at: convert(event.locationInWindow, from: nil)) { super.mouseDown(with: event) }
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let row else { return }
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: bounds).addClip()
        let x: (Int) -> CGFloat = { 16 + CGFloat($0) * 15 }
        let mid = bounds.height / 2
        if !filtered {
            for edge in row.edges {
                let top: CGFloat = edge.segment == 2 ? mid : 0
                let bottom: CGFloat = edge.segment == 1 ? mid : bounds.height
                let path = NSBezierPath(); path.move(to: NSPoint(x: x(edge.from), y: top))
                path.curve(to: NSPoint(x: x(edge.to), y: bottom), controlPoint1: NSPoint(x: x(edge.from), y: top + (bottom-top)*0.6), controlPoint2: NSPoint(x: x(edge.to), y: bottom - (bottom-top)*0.6))
                palette[edge.color % palette.count].setStroke(); path.lineWidth = 1.5; path.stroke()
            }
        }
        let position = x(filtered ? 0 : row.lane), color = palette[row.color % palette.count]
        let hasControl = !filtered && foldAction != nil
        let radius: CGFloat = hasControl ? 6 : 3
        if isHead {
            let ringRadius = radius+2
            let ring = NSBezierPath(ovalIn: NSRect(x: position-ringRadius, y: mid-ringRadius, width: ringRadius*2, height: ringRadius*2))
            NSColor.textBackgroundColor.setFill(); ring.fill(); color.setStroke(); ring.lineWidth = 1.6; ring.stroke()
        }
        // Keep the node centered on its lane; its permanent sign is also the fold control.
        let dot = NSBezierPath(ovalIn: NSRect(x: position-radius, y: mid-radius, width: radius*2, height: radius*2))
        color.setFill(); dot.fill()
        NSColor.textBackgroundColor.setStroke(); dot.lineWidth = 0.7; dot.stroke()
        if hasControl {
            let sign = NSBezierPath()
            sign.move(to: NSPoint(x: position-3, y: mid)); sign.line(to: NSPoint(x: position+3, y: mid))
            if isFolded {
                sign.move(to: NSPoint(x: position, y: mid-3)); sign.line(to: NSPoint(x: position, y: mid+3))
            }
            NSColor.textBackgroundColor.setStroke(); sign.lineWidth = 1.5; sign.lineCapStyle = .round; sign.stroke()
        }
    }
}

final class CommitCell: NSTableCellView {
    private var commit: Commit?
    private var labels: [ReferenceLabel] = []
    private var worktrees: [GitWorktree] = []
    private var laneColor = 0
    private var isHead = false
    private var activePath: String?
    private var foldedCount = 0
    var unfoldAction: (() -> Void)?
    private(set) var foldCounterRect = NSRect.zero
    private var referenceRegions: [(NSRect, ReferenceLabel)] = []
    private var remoteRegions: [(NSRect, String)] = []
    private var localRegions: [(NSRect, String)] = []
    private var worktreeRegions: [(NSRect, GitWorktree)] = []
    func contextTarget(at point: NSPoint) -> HistoryMenuTarget {
        guard bounds.contains(point) else { return .commit }
        if let tree = worktreeRegions.first(where: { $0.0.contains(point) })?.1 { return .worktree(tree.path) }
        if let remote = remoteRegions.first(where: { $0.0.contains(point) })?.1 { return .remoteBranch(remote) }
        if let local = localRegions.first(where: { $0.0.contains(point) })?.1 { return .localBranch(local) }
        if let reference = reference(at: point) { return .reference(reference) }
        return .commit
    }
    override var isFlipped: Bool { true }
    override var backgroundStyle: NSView.BackgroundStyle { didSet { needsDisplay = true } }
    func reference(at point: NSPoint) -> String? {
        guard bounds.contains(point) else { return nil }
        if let remote = remoteRegions.first(where: { $0.0.contains(point) }) { return remote.1 }
        guard let (box, label) = referenceRegions.first(where: { $0.0.contains(point) }) else { return nil }
        // A compound branch badge records origin in remoteRegions. Measuring italics inside the name box would steal clicks from the branch.
        let compound = remoteRegions.contains { label.fullNames.contains($0.1) }
        if !compound, !label.remotes.isEmpty {
            let font = NSFontManager.shared.convert(.systemFont(ofSize: 10), toHaveTrait: .italicFontMask)
            var right = box.maxX-5
            for index in label.remotes.indices.reversed() {
                let width = (label.remotes[index] as NSString).size(withAttributes: [.font: font]).width
                let left = max(box.minX+24, right-width)
                if point.x >= left && point.x <= right+2 && label.fullNames.indices.contains(index+1) { return label.fullNames[index+1] }
                right = left-7
            }
        }
        return label.fullNames.first
    }

    func configure(_ commit: Commit, labels: [ReferenceLabel], worktrees: [GitWorktree], color: Int, isHead: Bool, activePath: String? = nil, foldedCount: Int = 0) {
        self.commit = commit; self.labels = labels; self.worktrees = worktrees; laneColor = color; self.isHead = isHead; self.activePath = activePath; self.foldedCount = foldedCount
        referenceRegions.removeAll(keepingCapacity: true); remoteRegions.removeAll(keepingCapacity: true); localRegions.removeAll(keepingCapacity: true); worktreeRegions.removeAll(keepingCapacity: true); foldCounterRect = .zero
        toolTip = relationTooltip()
        setAccessibilityElement(true); setAccessibilityRole(.staticText)
        setAccessibilityLabel(accessibilitySummary())
        needsDisplay = true
    }
    @discardableResult func handleFoldClick(at point: NSPoint) -> Bool {
        guard foldedCount >= 2, !foldCounterRect.isEmpty, foldCounterRect.insetBy(dx: -4, dy: -4).contains(point), let unfoldAction else { return false }
        unfoldAction(); return true
    }
    override func mouseDown(with event: NSEvent) {
        if !handleFoldClick(at: convert(event.locationInWindow, from: nil)) { super.mouseDown(with: event) }
    }
    var foldSuffix: String {
        foldedCount > 0 ? " (\(foldedCount) commit\(foldedCount == 1 ? "" : "s") plié\(foldedCount == 1 ? "" : "s"))" : ""
    }
    private func workspace(matching label: ReferenceLabel) -> GitWorktree? {
        guard label.kind == .branch else { return nil }
        let ref = "refs/heads/" + label.name
        return worktrees.first { $0.branch == ref } ?? worktrees.first { $0.branch == nil && $0.assignedBranch == ref }
    }
    private func isCurrentWorkspace(_ tree: GitWorktree) -> Bool {
        guard let activePath else { return false }
        return Git.samePath(tree.path, activePath)
    }
    private func fileCount(_ count: Int) -> String { count == 1 ? "1 fichier" : "\(count) fichiers" }
    private func workspaceProse(_ tree: GitWorktree) -> String {
        if tree.associationIssue != nil { return "association incohérente" }
        if !tree.exists { return "dossier absent" }
        if tree.isLocked { return "verrouillé" }
        switch tree.changedFiles {
        case let count? where count > 0: return count == 1 ? "1 fichier modifié" : "\(count) fichiers modifiés"
        case .some: return "propre"
        case nil: return "état indisponible"
        }
    }
    private func originClause(_ remotes: [String]) -> String {
        guard let first = remotes.first?.lowercased().first else { return "" }
        let names = remotes.joined(separator: ", ")
        return "aeiouyàâäéèêëîïôöùûüh".contains(first) ? ", au même commit qu'\(names)" : ", au même commit que \(names)"
    }
    private func relationTooltip() -> String {
        var lines: [String] = []
        if let commit { lines.append(commit.subject + foldSuffix) }
        var claimed = Set<String>()
        for label in labels where label.kind != .tag {
            if label.kind == .remote {
                let whereRemote = label.remotes.isEmpty ? "" : " sur " + label.remotes.joined(separator: ", ")
                lines.append("\(label.name) pointe ce commit\(whereRemote). Pas de branche locale, pas de dossier.")
                continue
            }
            let same = originClause(label.remotes)
            if let tree = workspace(matching: label) {
                claimed.insert(tree.path)
                let place = isCurrentWorkspace(tree) ? "dans cette fenêtre (\(tree.path))" : "dans \(tree.path)"
                lines.append("\(label.name) est ouvert \(place), \(workspaceProse(tree))\(same).")
            } else {
                lines.append("\(label.name) n'a pas encore de dossier\(same).")
            }
        }
        for tree in worktrees where !claimed.contains(tree.path) {
            if tree.branch == nil { lines.append("Worktree détaché sur \(String(tree.head.prefix(8))). \(tree.path)") }
            else { lines.append("\(tree.branchLabel) est ouvert dans \(tree.path), \(workspaceProse(tree)).") }
        }
        for tag in labels where tag.kind == .tag { lines.append("Tag \(tag.name)") }
        if foldedCount >= 2 { lines.append("Cliquer sur le compteur pour déplier cette suite.") }
        return lines.joined(separator: "\n")
    }
    private func accessibilitySummary() -> String {
        var pieces = [commit?.subject ?? ""]
        if !foldSuffix.isEmpty, let subject = commit?.subject { pieces[0] = subject + foldSuffix }
        for label in labels {
            if label.kind == .tag { pieces.append(label.name); continue }
            var text = label.name
            if !label.remotes.isEmpty { text += ", " + label.remotes.joined(separator: ", ") }
            if label.kind == .branch { text += ", local" }
            if let tree = workspace(matching: label) { text += ", " + (tree.isMain ? "repository root " : "") + tree.path }
            pieces.append(text)
        }
        return pieces.joined(separator: ", ")
    }
    private var regionTips: [(NSRect, String)] = []
    @objc func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData: UnsafeMutableRawPointer?) -> String {
        regionTips.first { $0.0.contains(point) }?.1 ?? toolTip ?? ""
    }
    private func installRegionToolTips() {
        removeAllToolTips()
        for (rect, _) in regionTips where !rect.isEmpty { addToolTip(rect, owner: self, userData: nil) }
    }
    private func textWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
    private func badgeWidth(_ text: String, remote: String = "", bold: Bool = false) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 10.5, weight: bold ? .semibold : .regular)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width + (remote.isEmpty ? 0 : (remote as NSString).size(withAttributes: [.font: font]).width+9) + 31)
    }
    /// One pill for every branch: the same branch icon and name, then a computer for the local branch, the worktree icon, and one cloud per remote last.
    private func compoundBadge(_ label: ReferenceLabel, tree: GitWorktree?, color: NSColor, x: CGFloat, maxWidth: CGFloat) -> (width: CGFloat, name: NSRect, workspace: NSRect?)? {
        let bold = label.isCurrent
        let nameFont = NSFont.systemFont(ofSize: 10.5, weight: bold ? .semibold : .regular)
        let nameW = textWidth(label.name, font: nameFont)
        let remoteRefs = label.kind == .branch ? Array(label.fullNames.dropFirst()) : label.fullNames
        let remoteW: CGFloat = remoteRefs.isEmpty ? 0 : CGFloat(remoteRefs.count) * chipWidth
        let localW: CGFloat = label.kind == .branch ? chipWidth : 0
        let workspaceW: CGFloat = tree == nil ? 0 : chipWidth
        let chips = remoteW + localW + workspaceW
        let gap: CGFloat = chips > 0 ? 4 : 5
        let natural = ceil(24 + nameW + gap + chips)
        let minimum = ceil(24 + min(20, nameW) + gap + chips)
        guard maxWidth >= minimum else { return nil }
        let width = min(natural, 480, maxWidth)
        let box = NSRect(x: x, y: (bounds.height-18)/2, width: width, height: 18)
        let nameDraw = max(0, width - 24 - gap - chips)
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        let path = NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3)
        NSColor.textBackgroundColor.setFill(); path.fill()
        color.withAlphaComponent(0.07).setFill(); path.fill()
        color.withAlphaComponent(bold ? 1 : 0.6).setStroke(); path.lineWidth = bold ? 1.2 : 0.7; path.stroke()
        path.addClip(); color.setFill(); NSRect(x: box.minX, y: box.minY, width: 19, height: box.height).fill()
        drawMark("arrow.triangle.branch", tint: .white, weight: .bold, pointSize: 11, in: NSRect(x: box.minX, y: box.minY, width: 19, height: box.height))
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingMiddle
        let nameText = NSAttributedString(string: label.name, attributes: [.font: nameFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: style])
        nameText.draw(in: NSRect(x: x+24, y: box.minY+2, width: nameDraw, height: 15))
        var cursor = box.minX + 24 + nameDraw
        if chips > 0 { cursor += 4 }
        let chipsStart = cursor
        var workspaceRect: NSRect?
        if chips > 0 {
            let separator = NSBezierPath()
            separator.move(to: NSPoint(x: cursor, y: box.minY+3)); separator.line(to: NSPoint(x: cursor, y: box.maxY-3))
            NSColor.separatorColor.setStroke(); separator.lineWidth = 1; separator.stroke()
        }
        if localW > 0 {
            let chip = NSRect(x: cursor, y: box.minY, width: localW, height: box.height)
            drawComputer(tint: watermark, in: chip)
            if let local = label.fullNames.first { localRegions.append((chip, local)) }
            regionTips.append((chip, "Branch \(label.name) available locally"))
            cursor += localW
        }
        if let tree, workspaceW > 0 {
            let chip = NSRect(x: cursor, y: box.minY, width: workspaceW, height: box.height)
            drawWorktree(tree, in: chip)
            workspaceRect = chip
            regionTips.append((chip, tree.path))
            cursor += workspaceW
        }
        // Remotes come last: local, then worktree, then one cloud per remote.
        for (index, ref) in remoteRefs.enumerated() {
            let chip = NSRect(x: cursor, y: box.minY, width: chipWidth, height: box.height)
            drawCloud(tint: watermark, in: chip)
            remoteRegions.append((chip, ref))
            let remoteName = label.remotes.indices.contains(index) ? label.remotes[index] : ref
            regionTips.append((chip, "Branch \(label.name) available on \(remoteName)"))
            cursor += chipWidth
        }
        let nameLimit = chips > 0 ? chipsStart : box.maxX
        let nameRect = NSRect(x: box.minX, y: box.minY, width: max(19, nameLimit - box.minX), height: box.height)
        return (width, nameRect, workspaceRect)
    }
    /// Wider than the icons so each one is an easy hover and click target.
    private let chipWidth: CGFloat = 24
    private var watermark: NSColor { NSColor.labelColor.withAlphaComponent(0.6) }
    /// Draws a symbol at its natural proportions.
    private func drawMark(_ symbolName: String, tint: NSColor, weight: NSFont.Weight = .regular, pointSize: CGFloat = 10.5, in chip: NSRect) {
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: weight).applying(.init(paletteColors: [tint]))) else { return }
        let fit = min(1, (chip.width-2)/symbol.size.width, (chip.height-2)/symbol.size.height)
        let size = NSSize(width: symbol.size.width*fit, height: symbol.size.height*fit)
        symbol.draw(in: NSRect(x: chip.midX-size.width/2, y: chip.midY-size.height/2, width: size.width, height: size.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
    /// The repository root stands out by a bolder black stroke, never by colour.
    private func drawWorktree(_ tree: GitWorktree, in chip: NSRect) {
        drawStack(tint: tree.isMain ? .labelColor : watermark, lineWidth: tree.isMain ? 1.6 : 1, in: chip)
    }
    // The cloud, computer and stack are hand-drawn so they share one stroke. SF Symbols vary in weight, and their computers have a filled screen.
    private func center(of chip: NSRect) -> NSPoint { NSPoint(x: floor(chip.midX)+0.5, y: floor(chip.midY)+0.5) }
    private func strokeOutline(_ path: NSBezierPath, tint: NSColor, lineWidth: CGFloat = 1) {
        path.lineWidth = lineWidth; path.lineCapStyle = .round; path.lineJoinStyle = .round
        tint.setStroke(); path.stroke()
    }
    private func drawCloud(tint: NSColor, in chip: NSRect) {
        let c = center(of: chip), path = NSBezierPath()
        path.move(to: NSPoint(x: c.x-3.6, y: c.y+4))
        path.curve(to: NSPoint(x: c.x-3.9, y: c.y-1), controlPoint1: NSPoint(x: c.x-7.2, y: c.y+4), controlPoint2: NSPoint(x: c.x-7.2, y: c.y-0.8))
        path.curve(to: NSPoint(x: c.x+3.6, y: c.y-0.6), controlPoint1: NSPoint(x: c.x-3.2, y: c.y-5.6), controlPoint2: NSPoint(x: c.x+3, y: c.y-5.2))
        path.curve(to: NSPoint(x: c.x+3.6, y: c.y+4), controlPoint1: NSPoint(x: c.x+7, y: c.y-0.6), controlPoint2: NSPoint(x: c.x+7, y: c.y+4))
        path.close()
        strokeOutline(path, tint: tint)
    }
    private func drawComputer(tint: NSColor, in chip: NSRect) {
        let c = center(of: chip)
        let path = NSBezierPath(roundedRect: NSRect(x: c.x-6, y: c.y-5, width: 12, height: 8), xRadius: 1.2, yRadius: 1.2)
        path.move(to: NSPoint(x: c.x, y: c.y+3)); path.line(to: NSPoint(x: c.x, y: c.y+5))
        path.move(to: NSPoint(x: c.x-3, y: c.y+5)); path.line(to: NSPoint(x: c.x+3, y: c.y+5))
        strokeOutline(path, tint: tint)
    }
    private func drawStack(tint: NSColor, lineWidth: CGFloat = 1, in chip: NSRect) {
        let c = center(of: chip), path = NSBezierPath()
        path.move(to: NSPoint(x: c.x, y: c.y-5)); path.line(to: NSPoint(x: c.x+5.5, y: c.y-2.5))
        path.line(to: NSPoint(x: c.x, y: c.y)); path.line(to: NSPoint(x: c.x-5.5, y: c.y-2.5)); path.close()
        for offset: CGFloat in [0, 2.5] {
            path.move(to: NSPoint(x: c.x-5.5, y: c.y+offset)); path.line(to: NSPoint(x: c.x, y: c.y+2.5+offset)); path.line(to: NSPoint(x: c.x+5.5, y: c.y+offset))
        }
        strokeOutline(path, tint: tint, lineWidth: lineWidth)
    }
    private func badge(_ text: String, remote: String = "", icon: String, color: NSColor, x: CGFloat, width: CGFloat, bold: Bool = false) {
        guard width > 24 else { return }
        let box = NSRect(x: x, y: (bounds.height-18)/2, width: width, height: 18)
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        let path = NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3)
        NSColor.textBackgroundColor.setFill(); path.fill()
        color.withAlphaComponent(0.07).setFill(); path.fill()
        color.withAlphaComponent(bold ? 1 : 0.6).setStroke(); path.lineWidth = bold ? 1.2 : 0.7; path.stroke()
        path.addClip(); color.setFill(); NSRect(x: box.minX, y: box.minY, width: 19, height: box.height).fill()
        let symbol = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?.withSymbolConfiguration(.init(paletteColors: [.white]))
        symbol?.draw(in: NSRect(x: x+4, y: box.minY+3.5, width: 11, height: 11), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        let content = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 10.5, weight: bold ? .semibold : .regular), .foregroundColor: NSColor.labelColor])
        if !remote.isEmpty {
            let italic = NSFontManager.shared.convert(.systemFont(ofSize: 10), toHaveTrait: .italicFontMask)
            content.append(NSAttributedString(string: "  " + remote, attributes: [.font: italic, .foregroundColor: NSColor.secondaryLabelColor]))
        }
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingMiddle
        content.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: content.length))
        content.draw(in: NSRect(x: x+24, y: box.minY+2, width: max(0, width-29), height: 15))
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let commit else { return }
        referenceRegions.removeAll(keepingCapacity: true); remoteRegions.removeAll(keepingCapacity: true); localRegions.removeAll(keepingCapacity: true); worktreeRegions.removeAll(keepingCapacity: true); regionTips.removeAll(keepingCapacity: true); foldCounterRect = .zero
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: bounds).addClip()
        let branchColor = palette[laneColor % palette.count]
        var left: CGFloat = 5, right = bounds.width-6
        let tags = labels.filter { $0.kind == .tag }
        // Tags sit at the end of the description, like Git Graph, rather than being lost in a combined ref string.
        var tagBudget = min(230, bounds.width * 0.28)
        for (index, tag) in tags.reversed().enumerated() {
            let width = min(badgeWidth(tag.name), tagBudget)
            guard width > 45 else { break }
            right -= width
            referenceRegions.append((NSRect(x: right, y: (bounds.height-18)/2, width: width, height: 18), tag))
            badge(tag.name, icon: "tag", color: palette[(laneColor+index) % palette.count], x: right, width: width)
            right -= 5; tagBudget -= width+5
        }
        let branchLabels = labels.filter { $0.kind != .tag }
        let reserve = min(210, bounds.width*0.34)
        let budget = max(0, min(bounds.width*0.65, right-reserve-10))
        var claimed = Set<String>()
        func overflow(from index: Int) {
            let count = branchLabels.count-index
            guard count > 0 else { return }
            let text = "+\(count)" as NSString
            text.draw(at: NSPoint(x: left, y: (bounds.height-13)/2), withAttributes: [.font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor])
            left += 26
        }
        for (i, label) in branchLabels.enumerated() {
            let remaining = budget-(left-5)
            guard remaining > 45 else { overflow(from: i); break }
            let rest = i < branchLabels.count-1 ? CGFloat(32) : 0
            let tree = label.kind == .branch ? workspace(matching: label) : nil
            // A branch's worktree has no icon of its own: the branch menu opens, copies and deletes it.
            guard let drawn = compoundBadge(label, tree: nil, color: branchColor, x: left, maxWidth: remaining-rest) else { overflow(from: i); break }
            referenceRegions.append((drawn.name, label))
            if let tree { claimed.insert(tree.path) }
            left += drawn.width+5
            if i < branchLabels.count-1 && budget-(left-5) < 80 {
                overflow(from: i+1); break
            }
        }
        // Only a worktree with no branch on this row (detached) keeps a stack icon. Its path is the hover text.
        for tree in worktrees where !claimed.contains(tree.path) {
            let width = chipWidth
            guard right-left > width+80 else { break }
            let rect = NSRect(x: left, y: (bounds.height-18)/2, width: width, height: 18)
            worktreeRegions.append((rect, tree))
            regionTips.append((rect, tree.path))
            drawWorktree(tree, in: rect)
            left += width+5
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let selected = backgroundStyle == .emphasized
        let foreground: NSColor = selected ? .alternateSelectedControlTextColor : commit.parents.count > 1 && !isHead ? .secondaryLabelColor : .labelColor
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: isHead ? .semibold : .regular), .foregroundColor: foreground, .paragraphStyle: paragraph]
        let suffix = foldSuffix as NSString
        let suffixAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: selected ? NSColor.alternateSelectedControlTextColor : .controlAccentColor, .paragraphStyle: paragraph]
        let available = max(0, right-left)
        let suffixWidth = min(available, ceil(suffix.size(withAttributes: suffixAttributes).width))
        let descriptionWidth = max(0, available-suffixWidth)
        (commit.subject as NSString).draw(in: NSRect(x: left, y: (bounds.height-16)/2, width: descriptionWidth, height: 16), withAttributes: attributes)
        if foldedCount > 0 {
            let x = left + min(descriptionWidth, ceil((commit.subject as NSString).size(withAttributes: attributes).width))
            foldCounterRect = NSRect(x: x, y: (bounds.height-15)/2, width: suffixWidth, height: 15)
            suffix.draw(in: foldCounterRect, withAttributes: suffixAttributes)
        }
        installRegionToolTips()
    }
}
