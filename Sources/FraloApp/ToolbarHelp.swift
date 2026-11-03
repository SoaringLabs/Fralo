import AppKit
import FraloDesignSystem

/// Shared hover help for header icons. Native toolbar controls keep owning clicks and focus.
@MainActor
final class ToolbarHelp: NSResponder {
    static let initialDelay: TimeInterval = 0.4
    static let warmInterval: TimeInterval = 0.8
    static let fadeIn: TimeInterval = 0.12
    static let fadeOut: TimeInterval = 0.1

    struct Target {
        let item: NSToolbarItem
        let text: String
        weak var view: NSView?
    }
    private weak var owner: NSWindow?
    private(set) var targets: [Target] = []
    private var areas: [(NSView, NSTrackingArea)] = []
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var pending: DispatchWorkItem?
    private var version = 0
    private var warmUntil: TimeInterval = 0
    private(set) var hoveredItem: NSToolbarItem?
    private(set) var visibleText: String?
    let panel = HelpPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    let label = NSTextField(labelWithString: "")
    var preferences = DesignPreferences()
    private var reducedMotion: Bool { preferences.effectiveReduceMotion }

    init(window: NSWindow?) {
        owner = window
        super.init()
        panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = true
        panel.level = .floating; panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
        panel.contentView = HelpSurface()
        label.font = .systemFont(ofSize: 12); label.maximumNumberOfLines = 2
        label.lineBreakMode = .byWordWrapping
        label.setAccessibilityElement(false)
        panel.contentView?.addSubview(label)
        window?.acceptsMouseMovedEvents = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if event.type == .mouseMoved, event.window === self.owner,
                   self.owner?.isKeyWindow == true, self.owner?.attachedSheet == nil {
                    self.updatePointer(event.locationInWindow)
                } else { self.dismiss(resetWarmth: true) }
            }
            return event
        }
        for name in [NSWindow.didUpdateNotification, NSWindow.didResignKeyNotification,
                     NSWindow.willCloseNotification, NSWindow.willMoveNotification, NSWindow.didResizeNotification,
                     NSWindow.willMiniaturizeNotification, NSWindow.willBeginSheetNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if name == NSWindow.didUpdateNotification { self.resolveViews() }
                    else { self.dismiss(resetWarmth: true) }
                }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss(resetWarmth: true) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss(resetWarmth: true) }
        })
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit {
        pending?.cancel()
        if let monitor { NSEvent.removeMonitor(monitor) }
        observers.forEach(NotificationCenter.default.removeObserver)
        let areas = areas, panel = panel
        let cleanup: @MainActor () -> Void = {
            areas.forEach { $0.0.removeTrackingArea($0.1) }
            panel.parent?.removeChildWindow(panel); panel.orderOut(nil)
        }
        if Thread.isMainThread { MainActor.assumeIsolated { cleanup() } }
        else { DispatchQueue.main.async { cleanup() } }
    }

    func configure(_ entries: [(NSToolbarItem, String)]) {
        let previous = targets
        if previous.map({ ObjectIdentifier($0.item) }) != entries.map({ ObjectIdentifier($0.0) }) {
            areas.forEach { $0.0.removeTrackingArea($0.1) }; areas.removeAll()
        }
        targets = entries.map { item, text in
            Target(item: item, text: text, view: previous.first(where: { $0.item === item })?.view)
        }
        resolveViews()
        if let hoveredItem, !targets.contains(where: { $0.item === hoveredItem }) { dismiss(resetWarmth: true) }
        if let hoveredItem, let target = targets.first(where: { $0.item === hoveredItem }), visibleText != nil {
            present(target)
        }
    }

    /// Uses public view geometry and accessibility labels, without relying on AppKit private class names.
    func resolveViews() {
        guard let owner, let root = owner.contentView?.superview else { return }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let candidates = descendants(root).filter {
            let rect = $0.convert($0.bounds, to: nil)
            return !$0.isHiddenOrHasHiddenAncestor && rect.height > 0 && rect.height <= 52 && rect.width <= 100
                && rect.midY > owner.frame.height - 90
        }
        var changed = areas.isEmpty
        for index in targets.indices {
            let target = targets[index]
            let view = target.item.view ?? (target.view?.window === owner ? target.view : nil) ?? candidates.first {
                $0.toolTip == target.text || $0.accessibilityLabel() == target.item.label
            }
            if view !== target.view { targets[index].view = view; changed = true }
            // Suppress only the matching icon's native popup. Keep the localized help for assistive tech.
            if let view {
                if view.toolTip != nil { view.toolTip = nil }
                if view.accessibilityHelp() != target.text { view.setAccessibilityHelp(target.text) }
            }
        }
        if changed {
            areas.forEach { $0.0.removeTrackingArea($0.1) }; areas.removeAll()
            for target in targets {
                guard let view = target.view else { continue }
                let area = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .mouseEnteredAndExited, .activeInKeyWindow], owner: self)
                view.addTrackingArea(area); areas.append((view, area))
            }
        }
        if let hoveredItem, !targets.contains(where: { $0.item === hoveredItem && $0.view?.window === owner }) {
            dismiss(resetWarmth: true)
        }
    }
    override func mouseEntered(with event: NSEvent) {
        guard owner?.isKeyWindow == true, owner?.attachedSheet == nil else { return }
        updatePointer(event.locationInWindow)
    }
    override func mouseExited(with event: NSEvent) { updatePointer(event.locationInWindow) }

    func updatePointer(_ point: NSPoint) {
        let target = targets.first { target in
            guard let view = target.view, view.window === owner, !view.isHiddenOrHasHiddenAncestor else { return false }
            return view.bounds.contains(view.convert(point, from: nil))
        }
        hover(target?.item)
    }
    func hover(_ item: NSToolbarItem?) {
        guard item !== hoveredItem else { return }
        pending?.cancel(); version += 1
        guard let item, let target = targets.first(where: { $0.item === item }) else {
            dismiss(); return
        }
        hoveredItem = item
        let warm = visibleText != nil || ProcessInfo.processInfo.systemUptime < warmUntil
        if visibleText != nil { present(target); return }
        let currentVersion = version
        let work = DispatchWorkItem { [weak self, weak item] in
            MainActor.assumeIsolated {
                guard let self, self.version == currentVersion, let item, self.hoveredItem === item,
                      let target = self.targets.first(where: { $0.item === item }) else { return }
                self.pending = nil; self.present(target)
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (warm ? 0.06 : Self.initialDelay), execute: work)
    }
    private func present(_ target: Target) {
        guard let owner, let view = target.view, view.window === owner, !view.isHiddenOrHasHiddenAncestor else { return }
        let wasVisible = visibleText != nil
        visibleText = target.text; label.stringValue = target.text
        let textSize = label.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: 300, height: 100))
        let size = NSSize(width: ceil(textSize.width) + 20, height: ceil(textSize.height) + 14)
        let anchor = owner.convertToScreen(view.convert(view.bounds, to: nil))
        let screen = owner.screen?.visibleFrame ?? anchor.insetBy(dx: -500, dy: -500)
        let x = min(max(anchor.midX - size.width / 2, screen.minX + 8), screen.maxX - size.width - 8)
        let y = max(screen.minY + 8, anchor.minY - size.height - 8)
        panel.appearance = owner.effectiveAppearance
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
        label.frame = NSRect(x: 10, y: 7, width: size.width - 20, height: size.height - 14)
        panel.contentView?.needsDisplay = true
        if !wasVisible {
            panel.alphaValue = 0
            owner.addChildWindow(panel, ordered: .above); panel.orderFront(nil)
        }
        fade(to: 1, duration: Self.fadeIn)
    }
    func dismiss(resetWarmth: Bool = false) {
        pending?.cancel(); pending = nil; version += 1; hoveredItem = nil
        if visibleText != nil { warmUntil = ProcessInfo.processInfo.systemUptime + Self.warmInterval }
        if resetWarmth { warmUntil = 0 }
        visibleText = nil
        let currentVersion = version
        let finish = { [weak self] in
            guard let self, self.version == currentVersion, self.visibleText == nil else { return }
            self.panel.orderOut(nil); self.owner?.removeChildWindow(self.panel)
        }
        if reducedMotion || !panel.isVisible { panel.alphaValue = 0; finish(); return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeOut; panel.animator().alphaValue = 0
        } completionHandler: { MainActor.assumeIsolated { finish() } }
    }
    private func fade(to alpha: CGFloat, duration: TimeInterval) {
        if reducedMotion { panel.alphaValue = alpha; return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration; context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = alpha
        }
    }
}

@MainActor
final class HelpPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class HelpSurface: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        (subviews.first as? NSTextField)?.textColor = .windowBackgroundColor
    }
}
