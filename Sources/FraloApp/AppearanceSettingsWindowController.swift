import AppKit
import FraloDesignSystem

@MainActor
final class AppearanceSettingsWindowController: NSWindowController {
    let choices: VisualChoiceGroup
    private(set) var selection: AppAppearance
    var onChange: ((AppAppearance) -> Void)?

    init(selection: AppAppearance, onChange: @escaping (AppAppearance) -> Void) {
        self.selection = selection; self.onChange = onChange
        choices = VisualChoiceGroup(AppAppearance.allCases.map {
            VisualChoiceItem($0.title, symbol: "circle.lefthalf.filled", image: Self.thumbnail($0))
        }, label: "界面外观", selected: AppAppearance.allCases.firstIndex(of: selection), layout: .tiles(columns: 3, height: 146))
        choices.focusRingType = .none
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 324),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Fralo 设置"; window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        let root = NeutralSurface(); window.contentView = root
        let icon = NSImageView(image: NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: nil)!)
        icon.contentTintColor = .controlAccentColor; icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 32).isActive = true; icon.heightAnchor.constraint(equalToConstant: 32).isActive = true
        let heading = FraloStyle.stack([FraloStyle.text("外观", role: .title),
            FraloStyle.paragraph("选择浅色、深色，或随系统自动切换。")], spacing: 6)
        let title = FraloStyle.stack([icon, heading], axis: .horizontal, spacing: 14)
        let note = FraloStyle.paragraph("更改会自动保存，并即时应用到 Fralo 的工作窗口。")
        let column = FraloStyle.stack([title, choices, note], spacing: 22, fillWidth: true)
        column.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(column)
        NSLayoutConstraint.activate([column.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            column.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            column.topAnchor.constraint(equalTo: root.topAnchor, constant: 26),
            column.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -24)])
        choices.onChange = { [weak self] index in self?.onChange?(AppAppearance.allCases[index]) }
        set(selection); window.center(); window.recalculateKeyViewLoop()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func set(_ value: AppAppearance) {
        selection = value; choices.selectedIndex = AppAppearance.allCases.firstIndex(of: value)
        window?.appearance = value.appearance
    }
    func present() {
        showWindow(nil); window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Decorative, fixed-appearance UI illustrations; never screenshots or user image content.
    private static func thumbnail(_ value: AppAppearance) -> NSImage {
        NSImage(size: NSSize(width: 152, height: 96), flipped: false) { rect in
            func draw(_ appearance: NSAppearance.Name, clip: NSRect) {
                NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect: clip).addClip()
                NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).addClip()
                NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
                    NSColor.windowBackgroundColor.setFill(); NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
                    NSColor.labelColor.withAlphaComponent(0.06).setFill()
                    NSRect(x: 1, y: 77, width: 150, height: 18).fill()
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
}
