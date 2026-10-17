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
final class BatchTableView: NSTableView {
    var onDelete: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { onDelete?() } else { super.keyDown(with: event) }
    }
}

@MainActor
final class ThumbnailCell: NSTableCellView {
    let thumbnail = NSImageView()
    let title = label("")
    let detail = label("", size: 11, secondary: true)
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        let text = stack([title, detail], spacing: 4)
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(thumbnail); addSubview(text)
        title.lineBreakMode = .byTruncatingMiddle
        detail.lineBreakMode = .byTruncatingMiddle
        NSLayoutConstraint.activate([
            thumbnail.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            thumbnail.centerYAnchor.constraint(equalTo: centerYAnchor), thumbnail.widthAnchor.constraint(equalToConstant: 46), thumbnail.heightAnchor.constraint(equalToConstant: 80),
            text.leadingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: 12), text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8), text.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        textField = title; imageView = thumbnail
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor
final class PreviewCanvas: NSView {
    var image: CGImage? { didSet { needsDisplay = true } }
    var imageRect = NSRect.zero { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        NSGraphicsContext.saveGraphicsState()
        let rect = imageRect
        NSBezierPath(rect: rect).addClip()
        NSColor.controlBackgroundColor.setFill(); rect.fill()
        let tile: CGFloat = 8
        NSColor.quaternaryLabelColor.withAlphaComponent(0.10).setFill()
        var row = 0, y = rect.minY
        while y < rect.maxY {
            var x = rect.minX + (row % 2 == 0 ? 0 : tile)
            while x < rect.maxX { NSRect(x: x, y: y, width: tile, height: tile).fill(); x += tile * 2 }
            y += tile; row += 1
        }
        let native = NSImage(cgImage: image, size: rect.size)
        native.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        NSGraphicsContext.restoreGraphicsState()
    }
}

@MainActor
final class PreviewScrollView: NSScrollView {
    var onResize: (() -> Void)?
    override func layout() { super.layout(); onResize?() }
}
