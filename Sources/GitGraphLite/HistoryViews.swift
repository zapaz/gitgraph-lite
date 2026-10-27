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
    var isGroup = false
    override var isFlipped: Bool { true }
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
        if isGroup {
            for offset: CGFloat in [-3, 0, 3] {
                let mark = NSBezierPath(); mark.move(to: NSPoint(x: position-4, y: mid+offset)); mark.line(to: NSPoint(x: position+4, y: mid+offset))
                color.setStroke(); mark.lineWidth = 1.8; mark.stroke()
            }
            return
        }
        if isHead {
            let ring = NSBezierPath(ovalIn: NSRect(x: position-5, y: mid-5, width: 10, height: 10))
            NSColor.textBackgroundColor.setFill(); ring.fill(); color.setStroke(); ring.lineWidth = 1.6; ring.stroke()
        }
        let dot = NSBezierPath(ovalIn: NSRect(x: position-3, y: mid-3, width: 6, height: 6))
        color.setFill(); dot.fill()
        NSColor.textBackgroundColor.setStroke(); dot.lineWidth = 0.7; dot.stroke()
    }
}

final class CommitCell: NSTableCellView {
    private var commit: Commit?
    private var labels: [ReferenceLabel] = []
    private var worktrees: [GitWorktree] = []
    private var laneColor = 0
    private var isHead = false
    private var referenceRegions: [(NSRect, ReferenceLabel)] = []
    override var isFlipped: Bool { true }
    override var backgroundStyle: NSView.BackgroundStyle { didSet { needsDisplay = true } }
    func reference(at point: NSPoint) -> String? {
        guard let (box, label) = referenceRegions.first(where: { $0.0.contains(point) }) else { return nil }
        if !label.remotes.isEmpty {
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

    func configure(_ commit: Commit, labels: [ReferenceLabel], worktrees: [GitWorktree], color: Int, isHead: Bool) {
        self.commit = commit; self.labels = labels; self.worktrees = worktrees; laneColor = color; self.isHead = isHead
        referenceRegions.removeAll(keepingCapacity: true)
        toolTip = ([commit.subject] + labels.flatMap(\.fullNames) + worktrees.map { "Worktree: \($0.path) · \($0.branchLabel)" }).joined(separator: "\n")
        setAccessibilityElement(true); setAccessibilityRole(.staticText)
        setAccessibilityLabel(([commit.subject] + labels.map { $0.name + ($0.remotes.isEmpty ? "" : " (" + $0.remotes.joined(separator: ", ") + ")") }).joined(separator: ", "))
        needsDisplay = true
    }
    private func badgeWidth(_ text: String, remote: String = "", bold: Bool = false) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 10.5, weight: bold ? .semibold : .regular)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width + (remote.isEmpty ? 0 : (remote as NSString).size(withAttributes: [.font: font]).width+9) + 31)
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
        referenceRegions.removeAll(keepingCapacity: true)
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
        for (i, label) in branchLabels.enumerated() {
            let remaining = budget-(left-5)
            guard remaining > 45 else { break }
            let rest = i < branchLabels.count-1 ? CGFloat(32) : 0
            let width = min(badgeWidth(label.name, remote: label.remotes.joined(separator: ", "), bold: label.isCurrent), 440, remaining-rest)
            guard width > 35 else { break }
            referenceRegions.append((NSRect(x: left, y: (bounds.height-18)/2, width: width, height: 18), label))
            badge(label.name, remote: label.remotes.joined(separator: ", "), icon: label.kind == .remote ? "cloud" : "arrow.triangle.branch", color: branchColor, x: left, width: width, bold: label.isCurrent)
            left += width+5
            if i < branchLabels.count-1 && budget-(left-5) < 80 {
                let count = branchLabels.count-i-1
                let text = "+\(count)" as NSString
                text.draw(at: NSPoint(x: left, y: (bounds.height-13)/2), withAttributes: [.font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor])
                left += 26; break
            }
        }
        // Worktree occupancy stays visible without consuming several long branch-name badges.
        if !worktrees.isEmpty && right-left > 170 {
            let width: CGFloat = worktrees.count == 1 ? 23 : 37
            badge(worktrees.count == 1 ? "" : String(worktrees.count), icon: "square.stack.3d.up", color: .systemBlue, x: left, width: width+5)
            left += width+10
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let selected = backgroundStyle == .emphasized
        let foreground: NSColor = selected ? .alternateSelectedControlTextColor : commit.parents.count > 1 && !isHead ? .secondaryLabelColor : .labelColor
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: isHead ? .semibold : .regular), .foregroundColor: foreground, .paragraphStyle: paragraph]
        (commit.subject as NSString).draw(in: NSRect(x: left, y: (bounds.height-16)/2, width: max(0, right-left), height: 16), withAttributes: attributes)
    }
}
