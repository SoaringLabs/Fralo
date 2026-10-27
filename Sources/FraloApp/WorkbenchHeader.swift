import AppKit

@MainActor
private final class HeaderDocument: NSView {
    let name = NSTextField(labelWithString: "Fralo")
    let count = NSTextField(labelWithString: "")
    override var intrinsicContentSize: NSSize { NSSize(width: 220, height: 34) }
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 34))
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        name.lineBreakMode = .byTruncatingMiddle; name.maximumNumberOfLines = 1
        count.font = .systemFont(ofSize: 11); count.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [name, count]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
                                     stack.centerYAnchor.constraint(equalTo: centerYAnchor)])
        name.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor).isActive = true
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
    private(set) var actions: NSToolbarItemGroup!
    private var sidebarHidden = false

    init(owner: MainWindowController, splitView: NSSplitView, menu: NSMenu, sidebarHidden: Bool) {
        self.owner = owner; self.splitView = splitView; self.menu = menu
        self.sidebarHidden = sidebarHidden
        super.init()
        toolbar.delegate = self; toolbar.displayMode = .iconOnly; toolbar.allowsUserCustomization = false
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("add"), .init("sidebar"), .init("sidebarBoundary"), .init("document"), .flexibleSpace, .init("workspaceActions"), .init("more")]
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar).filter { !sidebarHidden || $0.rawValue != "sidebarBoundary" }
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
        if id.rawValue == "workspaceActions" {
            let images = [("doc.on.doc", "复制当前图片"), ("slider.horizontal.3", "出图设置")].map { NSImage(systemSymbolName: $0.0, accessibilityDescription: $0.1)! }
            let group = NSToolbarItemGroup(itemIdentifier: id, images: images, selectionMode: .momentary,
                                           labels: ["复制当前图片", "显示或隐藏出图设置"], target: self, action: #selector(performWorkspaceAction(_:)))
            group.label = "图片操作"; group.controlRepresentation = .expanded; group.isBordered = true
            group.autovalidates = false
            group.subitems.forEach { $0.autovalidates = false }
            actions = group
            return group
        }
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
        case "document": item.view = document; item.label = "当前图片"
        default: return nil
        }
        return item
    }
    @objc private func performWorkspaceAction(_ sender: NSToolbarItemGroup) {
        guard let owner else { return }
        if sender.selectedIndex == 0 { owner.copyCurrent(sender) }
        else if sender.selectedIndex == 1 { owner.toggleInspector(sender) }
    }
    func update(name: String, count: Int, sidebarHidden: Bool, inspectorVisible: Bool, canAdd: Bool, canCopy: Bool) {
        self.sidebarHidden = sidebarHidden
        document.name.stringValue = name; document.name.toolTip = name
        document.count.stringValue = count == 0 ? "添加图片，开始套框" : "\(count) 张图片"
        let boundary = toolbar.items.firstIndex { $0.itemIdentifier.rawValue == "sidebarBoundary" }
        if sidebarHidden, let boundary { toolbar.removeItem(at: boundary) }
        else if !sidebarHidden && boundary == nil { toolbar.insertItem(withItemIdentifier: .init("sidebarBoundary"), at: 2) }
        toolbar.items.first { $0.itemIdentifier.rawValue == "add" }?.isEnabled = canAdd
        if let actions {
            actions.subitems[0].isEnabled = canCopy
            let title = inspectorVisible ? "隐藏出图设置" : "显示出图设置"
            actions.subitems[1].label = title; actions.subitems[1].toolTip = title
            if let control = actions.view as? NSSegmentedControl {
                control.setEnabled(canCopy, forSegment: 0)
                control.setToolTip("复制当前图片", forSegment: 0); control.setToolTip(title, forSegment: 1)
            }
        }
    }
}
