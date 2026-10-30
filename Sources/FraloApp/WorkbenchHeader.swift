import AppKit

@MainActor
private final class HeaderDocument: NSView {
    let name = NSTextField(labelWithString: "Fralo")
    let count = NSTextField(labelWithString: "")
    override var intrinsicContentSize: NSSize { NSSize(width: 220, height: 34) }
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 34))
        name.font = .systemFont(ofSize: 14, weight: .semibold)
        name.lineBreakMode = .byTruncatingMiddle; name.maximumNumberOfLines = 1
        count.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .regular); count.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [name, count]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
                                     stack.centerYAnchor.constraint(equalTo: centerYAnchor)])
        widthAnchor.constraint(equalToConstant: 220).isActive = true
        name.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true
        count.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}

/// The native tracking separator gives the sidebar its own titlebar section.
@MainActor
final class WorkbenchHeader: NSObject, NSToolbarDelegate {
    let toolbar = NSToolbar(identifier: "FraloSectionedToolbar")
    private weak var owner: MainWindowController?
    private let splitView: NSSplitView
    private let menu: NSMenu
    private let document = HeaderDocument()
    private var sidebarHidden = false
    var controlViews: [NSView] { toolbar.items.compactMap(\.view) }
    var controlMenus: [NSMenu] { [menu] }

    init(owner: MainWindowController, splitView: NSSplitView, menu: NSMenu, sidebarHidden: Bool) {
        self.owner = owner; self.splitView = splitView; self.menu = menu
        self.sidebarHidden = sidebarHidden
        super.init()
        toolbar.delegate = self; toolbar.displayMode = .iconOnly; toolbar.allowsUserCustomization = false
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .init("add"), .init("sidebar"), .init("sidebarBoundary"), .init("document"), .flexibleSpace, .init("copyCurrent"), .init("exportCurrent"), .space, .init("inspector"), .space, .init("more")]
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar).enumerated().compactMap { index, id in
            // The list header owns “+” while the sidebar is visible; the toolbar takes it over when hidden.
            sidebarHidden ? (index == 0 || id.rawValue == "sidebarBoundary" ? nil : id) : (id.rawValue == "add" ? nil : id)
        }
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if id.rawValue == "sidebarBoundary" { return NSTrackingSeparatorToolbarItem(identifier: id, splitView: splitView, dividerIndex: 0) }
        if id.rawValue == "more" {
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.menu = menu; item.showsIndicator = false
            item.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "更多操作")
            item.label = "更多操作"; item.toolTip = "更多操作"; item.isBordered = true
            return item
        }
        // Adjacent command items automatically share native glass, with normal button spacing.
        // NSToolbarItemGroup is rendered as a tighter segmented control on the current OS.
        if id.rawValue == "copyCurrent" { return outputItem("copyCurrent", symbol: "doc.on.doc", title: "复制当前图片", action: #selector(MainWindowController.copyCurrent(_:))) }
        if id.rawValue == "exportCurrent" { return outputItem("exportCurrent", symbol: "square.and.arrow.up", title: "导出当前图片", action: #selector(MainWindowController.exportCurrent(_:))) }
        let item = NSToolbarItem(itemIdentifier: id); item.autovalidates = false
        switch id.rawValue {
        case "add":
            item.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "添加图片")
            item.label = "添加图片"; item.toolTip = "添加图片（⌘O）"; item.target = owner; item.action = #selector(MainWindowController.addImages(_:))
            item.isBordered = true; item.visibilityPriority = .user
        case "sidebar":
            item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "显示或隐藏图片列表")
            item.label = "图片列表"; item.toolTip = "显示或隐藏图片列表（⌃⌘S）"; item.target = owner; item.action = #selector(MainWindowController.toggleSidebar(_:))
            item.isBordered = true; item.visibilityPriority = .user
        case "inspector":
            item.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: "出图设置")
            item.label = "出图设置"; item.toolTip = "隐藏出图设置"
            item.target = owner; item.action = #selector(MainWindowController.toggleInspector(_:)); item.isBordered = true
        case "document": item.view = document; item.label = "当前图片"; item.isBordered = false
        default: return nil
        }
        return item
    }
    private func outputItem(_ identifier: String, symbol: String, title: String, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: .init(identifier))
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)!
        let button = NSButton(image: image, target: owner, action: action)
        button.bezelStyle = .toolbar; button.setButtonType(.momentaryPushIn)
        button.setAccessibilityLabel(title); button.toolTip = title
        // Match the Notes two-action cluster: 44 pt between the icon centers.
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        item.view = button
        item.label = title; item.toolTip = title; item.target = owner; item.action = action
        item.isBordered = true; item.autovalidates = false
        return item
    }
    func update(name: String, subtitle: String, sidebarHidden: Bool, inspectorVisible: Bool, canAdd: Bool, canCopy: Bool, canExport: Bool) {
        self.sidebarHidden = sidebarHidden
        document.name.stringValue = name; document.name.toolTip = name
        document.count.stringValue = subtitle
        let boundary = toolbar.items.firstIndex { $0.itemIdentifier.rawValue == "sidebarBoundary" }
        let add = toolbar.items.firstIndex { $0.itemIdentifier.rawValue == "add" }
        if sidebarHidden {
            if let boundary { toolbar.removeItem(at: boundary) }
            if toolbar.items.first?.itemIdentifier == .flexibleSpace { toolbar.removeItem(at: 0) }
            if add == nil { toolbar.insertItem(withItemIdentifier: .init("add"), at: 0) }
        } else {
            if let add { toolbar.removeItem(at: add) }
            if toolbar.items.first?.itemIdentifier != .flexibleSpace { toolbar.insertItem(withItemIdentifier: .flexibleSpace, at: 0) }
            if boundary == nil, let sidebar = toolbar.items.firstIndex(where: { $0.itemIdentifier.rawValue == "sidebar" }) {
                toolbar.insertItem(withItemIdentifier: .init("sidebarBoundary"), at: sidebar + 1)
            }
        }
        toolbar.items.first { $0.itemIdentifier.rawValue == "add" }?.isEnabled = canAdd
        let title = inspectorVisible ? "隐藏出图设置" : "显示出图设置"
        toolbar.items.first { $0.itemIdentifier.rawValue == "inspector" }?.toolTip = title
        toolbar.items.first { $0.itemIdentifier.rawValue == "copyCurrent" }?.isEnabled = canCopy
        toolbar.items.first { $0.itemIdentifier.rawValue == "exportCurrent" }?.isEnabled = canExport
    }
}
