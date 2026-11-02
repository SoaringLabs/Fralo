import FraloLocalization
import AppKit
import FraloDesignSystem

/// Inset rounded group in the System Settings style: caption above, hairline-separated rows inside,
/// optional footer below. Groups read by fill against the content ground; there is no visible border.
@MainActor
final class SettingsGroup: NSStackView {
    init(_ caption: String, rows: [NSView], footer: String? = nil) {
        super.init(frame: .zero)
        orientation = .vertical; alignment = .leading; spacing = 7
        let box = GroupSurface()
        var items: [NSView] = []
        for (index, row) in rows.enumerated() {
            if index > 0 { items.append(Hairline()) }
            items.append(row)
        }
        let column = FraloStyle.stack(items, spacing: 0, fillWidth: true)
        items.forEach { $0.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
        column.translatesAutoresizingMaskIntoConstraints = false; box.addSubview(column)
        NSLayoutConstraint.activate([column.topAnchor.constraint(equalTo: box.topAnchor), column.bottomAnchor.constraint(equalTo: box.bottomAnchor),
                                     column.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
                                     column.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14)])
        let label = FraloStyle.text(caption, secondary: true); label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.setAccessibilityRole(.staticText)
        addArrangedSubview(label)
        addArrangedSubview(box); box.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        if let footer {
            let note = NSTextField(wrappingLabelWithString: footer)
            note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor
            addArrangedSubview(note); note.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor).isActive = true
        }
        arrangedSubviews.filter { $0 !== box }.forEach { $0.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2).isActive = true }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    /// Title and optional explanation on the leading side, one control trailing. `leading` places a status icon before the text.
    static func row(_ title: String, detail: String?, control: NSView? = nil, leading: NSView? = nil, enabled: Bool = true,
                    searchID: String? = nil) -> NSView {
        let name = NSTextField(wrappingLabelWithString: title); name.font = .systemFont(ofSize: 13)
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        var texts: [NSView] = [name]
        if let detail {
            let label = NSTextField(wrappingLabelWithString: detail)
            label.font = .systemFont(ofSize: 11); label.textColor = .secondaryLabelColor
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            texts.append(label)
        }
        let text = FraloStyle.stack(texts, spacing: 3)
        // Stack views resist clipping at required priority, which would widen the window for long translations; wrap instead.
        text.setClippingResistancePriority(.defaultLow, for: .horizontal)
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // Disabled text dims like the control beside it; its explanation stays readable in the row above.
        if !enabled { texts.forEach { ($0 as? NSTextField)?.textColor = .disabledControlTextColor } }
        let row = SettingsRowView(searchID: searchID)
        var lead = row.leadingAnchor
        var constraints: [NSLayoutConstraint] = [row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)]
        if let leading {
            leading.translatesAutoresizingMaskIntoConstraints = false; row.addSubview(leading)
            constraints += [leading.leadingAnchor.constraint(equalTo: row.leadingAnchor), leading.topAnchor.constraint(equalTo: text.topAnchor, constant: 1),
                            leading.widthAnchor.constraint(equalToConstant: 16), leading.heightAnchor.constraint(equalToConstant: 16)]
            lead = leading.trailingAnchor
        }
        text.translatesAutoresizingMaskIntoConstraints = false; row.addSubview(text)
        constraints += [text.leadingAnchor.constraint(equalTo: lead, constant: leading == nil ? 0 : 10), text.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                        text.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor, constant: 11)]
        if let control {
            control.translatesAutoresizingMaskIntoConstraints = false; row.addSubview(control)
            control.setContentCompressionResistancePriority(.required, for: .horizontal)
            // A push button names itself; switches, pickers and pop-up menus (whose title is the current value) take the row title.
            if control is NSPopUpButton || (control as? NSButton)?.title.isEmpty != false { control.setAccessibilityLabel(title) }
            constraints += [control.leadingAnchor.constraint(greaterThanOrEqualTo: text.trailingAnchor, constant: 20),
                            control.trailingAnchor.constraint(equalTo: row.trailingAnchor), control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                            control.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor, constant: 11)]
        } else {
            constraints.append(text.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor))
        }
        // Collapse to the taller of text or control plus padding, never below the 44 pt row height.
        let compact = row.heightAnchor.constraint(equalToConstant: 44); compact.priority = .defaultLow
        NSLayoutConstraint.activate(constraints + [compact])
        return row
    }

    private final class Hairline: NSView {
        override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 1) }
        override func draw(_ dirtyRect: NSRect) {
            // withAlphaComponent would replace separatorColor's own low alpha, so draw a fixed 8% ink.
            NSColor(white: isDark ? 1 : 0, alpha: highContrast ? 0.3 : 0.08).setFill()
            // Pixel-aligned at the bottom edge so it stays one device pixel instead of blurring across two.
            NSRect(x: 0, y: 0, width: bounds.width, height: 1 / max(1, window?.backingScaleFactor ?? 2)).fill()
        }
        override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    }
    private final class GroupSurface: NSView {
        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
            NSColor(white: isDark ? 1 : 0, alpha: isDark ? 0.05 : 0.035).setFill(); path.fill()
            // Increased contrast restores an edge, matching the system's own grouped forms.
            if highContrast {
                let edge = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
                NSColor.separatorColor.setStroke(); edge.lineWidth = 1; edge.stroke()
            }
        }
        override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    }
}

/// A settings row that search can point at: a soft accent wash behind it while it matches the query.
@MainActor
final class SettingsRowView: NSView {
    let searchID: String?
    private let highlight = Highlight()
    var isHighlighted = false {
        didSet {
            highlight.isHidden = !isHighlighted
            setAccessibilityValueDescription(isHighlighted ? L10n.tr("与搜索匹配") : nil)
        }
    }

    init(searchID: String?) {
        self.searchID = searchID
        super.init(frame: .zero)
        highlight.isHidden = true; highlight.translatesAutoresizingMaskIntoConstraints = false
        addSubview(highlight)
        // Reaches into the group's 14 pt inset so the wash frames the text rather than touching it.
        NSLayoutConstraint.activate([highlight.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -8),
                                     highlight.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 8),
                                     highlight.topAnchor.constraint(equalTo: topAnchor, constant: 4),
                                     highlight.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    private final class Highlight: NSView {
        override func draw(_ dirtyRect: NSRect) {
            NSColor.controlAccentColor.withAlphaComponent(highContrast ? 0.28 : 0.14).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    }
}

private extension NSView {
    var isDark: Bool { effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
    var highContrast: Bool { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }
}

/// Settings content ground: white in Light Mode, near-black in Dark Mode, so groups read by fill alone.
@MainActor
final class SettingsContentSurface: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) { NSColor.textBackgroundColor.setFill(); bounds.fill() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

/// Plain thumbnails with an accent ring on the selection and the name below; no card behind each option.
/// Reports as a radio group; arrow keys move the selection once the group has focus.
@MainActor
final class AppearanceThumbnailPicker: NSStackView {
    private(set) var selection: AppAppearance
    var onChange: ((AppAppearance) -> Void)?
    private(set) var buttons: [NSButton] = []

    init(selection: AppAppearance, onChange: ((AppAppearance) -> Void)? = nil) {
        self.selection = selection; self.onChange = onChange
        super.init(frame: .zero)
        orientation = .horizontal; spacing = 14; alignment = .top
        setAccessibilityElement(true); setAccessibilityRole(.radioGroup); setAccessibilityLabel(L10n.tr("外观"))
        for value in AppAppearance.allCases {
            let button = ThumbnailButton(title: value.title, target: self, action: #selector(choose(_:)))
            button.isBordered = false; button.imagePosition = .imageAbove; button.imageHugsTitle = true
            button.setButtonType(.onOff); button.setAccessibilityRole(.radioButton)
            button.onArrow = { [weak self] step in self?.move(step) }
            buttons.append(button); addArrangedSubview(button)
        }
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func select(_ value: AppAppearance) { selection = value; refresh() }
    @objc private func choose(_ sender: NSButton) {
        guard let index = buttons.firstIndex(of: sender) else { return }
        commit(AppAppearance.allCases[index])
    }
    private func move(_ step: Int) {
        let cases = AppAppearance.allCases
        guard let index = cases.firstIndex(of: selection) else { return }
        let next = min(max(index + step, 0), cases.count - 1)
        guard next != index else { return }
        commit(cases[next]); window?.makeFirstResponder(buttons[next])
    }
    private func commit(_ value: AppAppearance) {
        let changed = value != selection
        selection = value; refresh()
        if changed { onChange?(value) }
    }
    private func refresh() {
        for (button, value) in zip(buttons, AppAppearance.allCases) {
            let on = value == selection
            button.state = on ? .on : .off
            button.image = Self.thumbnail(value, selected: on)
            button.attributedTitle = NSAttributedString(string: value.title, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: on ? .semibold : .regular),
                .foregroundColor: on ? NSColor.labelColor : NSColor.secondaryLabelColor
            ])
            button.setAccessibilityValue(on ? 1 : 0)
        }
    }

    static func thumbnail(_ value: AppAppearance, selected: Bool) -> NSImage {
        let base = artwork(value)
        let image = NSImage(size: NSSize(width: 74, height: 52), flipped: false) { _ in
            let inner = NSRect(x: 4, y: 4, width: 66, height: 44)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: inner, xRadius: 7, yRadius: 7).addClip()
            base.draw(in: inner)
            NSGraphicsContext.restoreGraphicsState()
            if selected {
                let ring = NSBezierPath(roundedRect: inner.insetBy(dx: -3, dy: -3), xRadius: 9.5, yRadius: 9.5)
                ring.lineWidth = 2; NSColor.controlAccentColor.setStroke(); ring.stroke()
            } else {
                let edge = NSBezierPath(roundedRect: inner.insetBy(dx: 0.25, dy: 0.25), xRadius: 7, yRadius: 7)
                edge.lineWidth = 0.5; NSColor.separatorColor.setStroke(); edge.stroke()
            }
            return true
        }
        image.accessibilityDescription = value.title
        return image
    }

    /// Decorative, fixed-appearance UI illustrations; never screenshots or user image content.
    static func artwork(_ value: AppAppearance) -> NSImage {
        NSImage(size: NSSize(width: 152, height: 96), flipped: false) { rect in
            func draw(_ appearance: NSAppearance.Name, clip: NSRect) {
                NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect: clip).addClip()
                NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
                    NSColor.windowBackgroundColor.setFill(); rect.fill()
                    NSColor.labelColor.withAlphaComponent(0.06).setFill()
                    NSRect(x: 0, y: 78, width: 152, height: 18).fill()
                    NSColor.controlBackgroundColor.withAlphaComponent(0.8).setFill()
                    NSBezierPath(roundedRect: NSRect(x: 8, y: 8, width: 27, height: 62), xRadius: 5, yRadius: 5).fill()
                    NSBezierPath(roundedRect: NSRect(x: 112, y: 8, width: 32, height: 62), xRadius: 5, yRadius: 5).fill()
                    NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
                    NSBezierPath(roundedRect: NSRect(x: 12, y: 49, width: 19, height: 13), xRadius: 3, yRadius: 3).fill()
                    NSColor.labelColor.withAlphaComponent(0.16).setFill()
                    for y in [23, 33, 43, 57] { NSBezierPath(roundedRect: NSRect(x: 118, y: y, width: 20, height: 3), xRadius: 1.5, yRadius: 1.5).fill() }
                    NSColor.labelColor.withAlphaComponent(0.75).setFill()
                    NSBezierPath(roundedRect: NSRect(x: 59, y: 12, width: 34, height: 59), xRadius: 7, yRadius: 7).fill()
                    NSColor.windowBackgroundColor.setFill()
                    NSBezierPath(roundedRect: NSRect(x: 61, y: 14, width: 30, height: 55), xRadius: 5, yRadius: 5).fill()
                    NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
                    NSBezierPath(roundedRect: NSRect(x: 65, y: 32, width: 22, height: 29), xRadius: 3, yRadius: 3).fill()
                }
                NSGraphicsContext.restoreGraphicsState()
            }
            if value == .system {
                draw(.aqua, clip: NSRect(x: 0, y: 0, width: 76, height: 96))
                draw(.darkAqua, clip: NSRect(x: 76, y: 0, width: 76, height: 96))
            } else { draw(value == .light ? .aqua : .darkAqua, clip: rect) }
            return true
        }
    }

    private final class ThumbnailButton: NSButton {
        var onArrow: ((Int) -> Void)?
        override func keyDown(with event: NSEvent) {
            switch event.specialKey {
            case .leftArrow?, .upArrow?: onArrow?(-1)
            case .rightArrow?, .downArrow?: onArrow?(1)
            default: super.keyDown(with: event)
            }
        }
    }
}
