import AppKit
import GitGraphCore

private final class UnifiedLayout: NSLayoutManager {
    weak var viewer: UnifiedDiffView?
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        if let viewer, let container = textContainers.first, !viewer.model.lines.isEmpty {
            let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
            for i in viewer.indices(intersecting: characters) {
                let line = viewer.model.lines[i]
                let fill: NSColor?
                switch line.kind {
                case .removed: fill = NSColor.systemRed.withAlphaComponent(0.10)
                case .added: fill = NSColor.systemGreen.withAlphaComponent(0.10)
                case .hunk: fill = NSColor.systemBlue.withAlphaComponent(0.08)
                case .note: fill = NSColor.controlBackgroundColor
                default: fill = nil
                }
                guard let fill else { continue }
                let glyphs = glyphRange(forCharacterRange: viewer.range(of: i), actualCharacterRange: nil)
                enumerateLineFragments(forGlyphRange: NSIntersectionRange(glyphs, glyphsToShow)) { rect, _, _, _, _ in
                    let full = NSRect(x: 0, y: rect.minY + origin.y, width: max(viewer.text.bounds.width, container.size.width.isFinite ? min(container.size.width, viewer.text.bounds.width) : 0), height: rect.height)
                    fill.setFill(); full.fill()
                }
            }
        }
        // NSTextStorage's character backgrounds draw the more saturated word highlights.
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }
}

private final class UnifiedGutter: NSRulerView {
    weak var viewer: UnifiedDiffView?
    override var isFlipped: Bool { true }
    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor.controlBackgroundColor.setFill(); bounds.fill()
        NSColor.separatorColor.setFill(); NSRect(x: bounds.maxX-1, y: bounds.minY, width: 1, height: bounds.height).fill()
        guard let viewer, let container = viewer.text.textContainer, let layout = viewer.text.layoutManager else { return }
        layout.ensureLayout(for: container)
        let glyphs = layout.glyphRange(forBoundingRect: viewer.text.visibleRect, in: container)
        let chars = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        for i in viewer.indices(intersecting: chars) {
            let line = viewer.model.lines[i]
            let glyph = layout.glyphIndexForCharacter(at: viewer.offsets[i])
            guard glyph < layout.numberOfGlyphs else { continue }
            let fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let point = convert(NSPoint(x: 0, y: fragment.minY + viewer.text.textContainerOrigin.y), from: viewer.text)
            let color: NSColor = line.kind == .removed ? .systemRed : line.kind == .added ? .systemGreen : .tertiaryLabelColor
            if line.kind == .removed || line.kind == .added {
                color.withAlphaComponent(0.13).setFill()
                NSRect(x: 0, y: point.y, width: bounds.width-1, height: fragment.height).fill()
            }
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            func number(_ value: Int?, right: CGFloat) {
                guard let value else { return }
                let text = String(value) as NSString
                let size = text.size(withAttributes: attributes)
                text.draw(at: NSPoint(x: right-size.width, y: point.y + 3), withAttributes: attributes)
            }
            number(line.oldNumber, right: 39); number(line.newNumber, right: 82)
            let marker = line.kind == .removed ? "−" : line.kind == .added ? "+" : line.kind == .hunk ? "⋯" : ""
            (marker as NSString).draw(at: NSPoint(x: 94, y: point.y+3), withAttributes: attributes)
            if viewer.activeChange == i {
                NSColor.controlAccentColor.setFill(); NSRect(x: 0, y: point.y, width: 3, height: fragment.height).fill()
            }
        }
    }
}

final class UnifiedDiffView: NSView {
    let scroll = NSScrollView()
    let text: NSTextView
    private let diffLayout: UnifiedLayout
    private var gutter: UnifiedGutter!
    var model = UnifiedDiff(VisualDiff.parse(""))
    var offsets: [Int] = []
    var activeChange: Int?
    var wrapped = true
    private let comparison = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        let storage = NSTextStorage(), container = NSTextContainer(containerSize: NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude))
        let layout = UnifiedLayout(); diffLayout = layout
        storage.addLayoutManager(layout); layout.addTextContainer(container)
        text = NSTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 300), textContainer: container)
        super.init(frame: frame)
        diffLayout.viewer = self
        text.isEditable = false; text.isSelectable = true; text.isRichText = false
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        text.textContainerInset = NSSize(width: 12, height: 10)
        text.isVerticallyResizable = true; text.minSize = .zero
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = text; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        gutter = UnifiedGutter(scrollView: scroll, orientation: .verticalRuler)
        gutter.viewer = self; gutter.clientView = text; gutter.ruleThickness = 114
        scroll.verticalRulerView = gutter; scroll.hasVerticalRuler = true; scroll.rulersVisible = true
        let old = NSTextField(labelWithString: "OLD"), new = NSTextField(labelWithString: "NEW"), spacer = NSView()
        for label in [old, new] { label.font = .systemFont(ofSize: 9, weight: .semibold); label.textColor = .secondaryLabelColor; label.alignment = .right; label.widthAnchor.constraint(equalToConstant: 43).isActive = true }
        spacer.widthAnchor.constraint(equalToConstant: 28).isActive = true
        comparison.font = .systemFont(ofSize: 10, weight: .medium); comparison.textColor = .secondaryLabelColor; comparison.lineBreakMode = .byTruncatingMiddle
        let legend = NSStackView(views: [old, new, spacer, comparison]); legend.spacing = 0; legend.distribution = .fill
        comparison.setContentHuggingPriority(.defaultLow, for: .horizontal)
        legend.translatesAutoresizingMaskIntoConstraints = false; addSubview(legend)
        scroll.translatesAutoresizingMaskIntoConstraints = false; addSubview(scroll)
        NSLayoutConstraint.activate([legend.leadingAnchor.constraint(equalTo: leadingAnchor), legend.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12), legend.topAnchor.constraint(equalTo: topAnchor), legend.heightAnchor.constraint(equalToConstant: 24), scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor), scroll.topAnchor.constraint(equalTo: legend.bottomAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor)])
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        setWrapped(true)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc func scrolled() { gutter.needsDisplay = true }
    override func layout() { super.layout(); if wrapped { text.setFrameSize(NSSize(width: scroll.contentSize.width, height: max(text.frame.height, scroll.contentSize.height))) }; gutter.needsDisplay = true }
    func setWrapped(_ wrap: Bool) {
        wrapped = wrap
        text.isHorizontallyResizable = !wrap; text.autoresizingMask = wrap ? [.width] : []
        text.textContainer?.widthTracksTextView = wrap
        text.textContainer?.containerSize = NSSize(width: wrap ? max(100, scroll.contentSize.width-24) : CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.hasHorizontalScroller = !wrap
        if wrap { text.setFrameSize(NSSize(width: scroll.contentSize.width, height: max(text.frame.height, scroll.contentSize.height))) }
        else { text.sizeToFit() }
        text.needsDisplay = true; gutter?.needsDisplay = true
    }
    func range(of line: Int) -> NSRange {
        let end = line+1 < offsets.count ? offsets[line+1] : (text.string as NSString).length
        return NSRange(location: offsets[line], length: end-offsets[line])
    }
    func indices(intersecting range: NSRange) -> Range<Int> {
        guard !offsets.isEmpty else { return 0..<0 }
        var low = 0, high = offsets.count
        while low < high { let mid = (low+high)/2; if offsets[mid] <= range.location { low = mid+1 } else { high = mid } }
        let first = max(0, low-1)
        var end = first
        while end < offsets.count && offsets[end] <= NSMaxRange(range) { end += 1 }
        return first..<end
    }
    func showMessage(_ message: String) {
        model = UnifiedDiff(VisualDiff.parse("")); offsets = []; activeChange = nil
        text.string = message; scroll.rulersVisible = false
        comparison.stringValue = ""
    }
    func show(_ diff: VisualDiff, rawPatch: String, before: String, after: String) {
        model = UnifiedDiff(diff); offsets = []; activeChange = nil
        guard !model.lines.isEmpty else { showMessage(rawPatch); return }
        comparison.stringValue = "\(before) → \(after)   ·   \(model.changeStarts.count) change\(model.changeStarts.count == 1 ? "" : "s")"
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 3; paragraph.defaultTabInterval = 28; paragraph.tabStops = []
        let result = NSMutableAttributedString(string: "")
        for line in model.lines {
            offsets.append(result.length)
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: line.kind == .hunk ? 11 : 12, weight: line.kind == .hunk ? .medium : .regular), .foregroundColor: line.kind == .hunk ? NSColor.systemBlue : line.kind == .note ? NSColor.secondaryLabelColor : NSColor.labelColor, .paragraphStyle: paragraph]
            let start = result.length
            result.append(NSAttributedString(string: line.text + "\n", attributes: attributes))
            if let range = line.highlight {
                let color: NSColor = line.kind == .removed ? .systemRed : .systemGreen
                result.addAttribute(.backgroundColor, value: color.withAlphaComponent(0.26), range: NSRange(location: start+range.location, length: range.length))
            }
        }
        text.textStorage?.setAttributedString(result)
        scroll.rulersVisible = true; setWrapped(wrapped)
        text.scrollToBeginningOfDocument(nil); gutter.needsDisplay = true
    }
    func revealChange(_ index: Int) {
        guard model.changeStarts.indices.contains(index) else { return }
        let line = model.changeStarts[index]
        activeChange = line
        let start = max(0, line-2)
        text.scrollRangeToVisible(NSUnionRange(range(of: start), range(of: line)))
        text.showFindIndicator(for: range(of: line)); gutter.needsDisplay = true
    }
}
