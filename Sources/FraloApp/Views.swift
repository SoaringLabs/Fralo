import AppKit
import FraloCore

@MainActor
func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = secondary ? .secondaryLabelColor : .labelColor
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return field
}

@MainActor
func stack(_ views: [NSView], orientation: NSUserInterfaceLayoutOrientation = .vertical, spacing: CGFloat = 12) -> NSStackView {
    let view = NSStackView(views: views); view.orientation = orientation; view.spacing = spacing
    view.alignment = orientation == .vertical ? .leading : .centerY
    return view
}

@MainActor
func separator() -> NSBox { let box = NSBox(); box.boxType = .separator; return box }

@MainActor
final class DropContainer: NSView {
    var onDrop: (([URL]) -> Void)?
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return false }
        onDrop?(urls); return true
    }
}

@MainActor
final class PreviewScrollView: NSScrollView {
    var onResize: (() -> Void)?
    var onScroll: (() -> Void)?
    override func layout() { super.layout(); onResize?() }
    override func reflectScrolledClipView(_ clipView: NSClipView) { super.reflectScrolledClipView(clipView); onScroll?() }
}
