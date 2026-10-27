import AppKit

/// Stable application roles. Artwork colors belong to the renderer, not this palette.
@MainActor
public enum FraloStyle {
    public enum Button {
        public static let height: CGFloat = 34
        public static let compactHeight: CGFloat = 28
        public static let radius: CGFloat = 10
        public static let compactRadius: CGFloat = 7
        public static let inset: CGFloat = 16
        public static let compactInset: CGFloat = 12
        public static let icon: CGFloat = 14
        public static let compactIcon: CGFloat = 14
    }

    public enum Workbench {
        public static let panelRadius: CGFloat = 24
        public static let panelInset: CGFloat = 18
        public static let rowHeight: CGFloat = 148
        public static let controlHeight: CGFloat = 30
    }

    public enum Space {
        public static let small: CGFloat = 4
        public static let control: CGFloat = 8
        public static let row: CGFloat = 12
        public static let inset: CGFloat = 16
        public static let section: CGFloat = 24
        public static let large: CGFloat = 32
    }

    public enum TextRole: String, CaseIterable {
        case title, heading, body, detail, caption
        public var font: NSFont {
            switch self {
            case .title: return .systemFont(ofSize: 23, weight: .semibold)
            case .heading: return .systemFont(ofSize: 15, weight: .semibold)
            case .body: return .systemFont(ofSize: 13)
            case .detail: return .systemFont(ofSize: 12)
            case .caption: return .systemFont(ofSize: 11)
            }
        }
    }

    public static func text(_ value: String, role: TextRole = .body, secondary: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: value)
        field.font = role.font
        field.textColor = secondary ? .secondaryLabelColor : .labelColor
        field.lineBreakMode = .byTruncatingMiddle
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    public static func paragraph(_ value: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: value)
        field.font = TextRole.detail.font
        field.textColor = .secondaryLabelColor
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    public static func stack(_ views: [NSView], axis: NSUserInterfaceLayoutOrientation = .vertical,
                             spacing: CGFloat = Space.row, fillWidth: Bool = false) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = axis
        stack.alignment = axis == .vertical ? .leading : .centerY
        stack.spacing = spacing
        if axis == .vertical && fillWidth {
            for view in views { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        }
        return stack
    }

    public static func divider() -> NSBox {
        let line = NSBox(); line.boxType = .separator; return line
    }

    public static func configure(_ control: NSControl, size: NSControl.ControlSize = .regular) {
        control.controlSize = size
        control.font = .systemFont(ofSize: NSFont.systemFontSize(for: size))
    }
}

/// Per-preview requests may strengthen accessibility settings, never weaken the OS setting.
public struct DesignPreferences: Equatable {
    public var reduceTransparency = false
    public var reduceMotion = false
    public var increaseContrast = false
    public init() {}

    @MainActor public var effectiveReduceTransparency: Bool {
        reduceTransparency || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
    @MainActor public var effectiveReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    @MainActor public var effectiveIncreaseContrast: Bool {
        increaseContrast || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }
}

@MainActor
public enum FraloMotion {
    public enum Transition { case selection, structure, preview }
    public static func duration(_ transition: Transition, preferences: DesignPreferences = .init()) -> TimeInterval {
        guard !preferences.effectiveReduceMotion else { return 0 }
        switch transition {
        case .selection: return 0.18
        case .structure: return 0.22
        case .preview: return 0.16
        }
    }
}

@MainActor
public final class NeutralSurface: NSView {
    public override var isOpaque: Bool { true }
    public override func draw(_ dirtyRect: NSRect) { NSColor.windowBackgroundColor.setFill(); bounds.fill() }
    public override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

@MainActor
public final class FormRow: NSStackView {
    public init(_ title: String, content: NSView) {
        super.init(frame: .zero)
        orientation = .horizontal; alignment = .centerY; spacing = FraloStyle.Space.row
        let label = FraloStyle.text(title)
        label.widthAnchor.constraint(equalToConstant: 88).isActive = true
        addArrangedSubview(label); addArrangedSubview(content)
        if let control = content as? NSControl { control.setAccessibilityLabel(title) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}

@MainActor
public final class InfoRow: NSStackView {
    public let value: NSTextField
    public init(_ title: String, value: String) {
        self.value = FraloStyle.text(value)
        super.init(frame: .zero)
        orientation = .horizontal; alignment = .firstBaseline; spacing = 12
        let label = FraloStyle.text(title, secondary: true)
        addArrangedSubview(label); addArrangedSubview(NSView()); addArrangedSubview(self.value)
        self.value.isSelectable = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}

@MainActor
public final class FormSection: NSStackView {
    public init(_ title: String, detail: String? = nil, views: [NSView]) {
        super.init(frame: .zero)
        orientation = .vertical; alignment = .leading; spacing = FraloStyle.Space.row
        addArrangedSubview(FraloStyle.text(title, role: .heading))
        if let detail { addArrangedSubview(FraloStyle.paragraph(detail)) }
        for view in views {
            addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}
