import AppKit
import XCTest
import FraloCore
import FraloDesignSystem
@testable import FraloApp

final class PanelPolishTests: XCTestCase {
    @MainActor func testFixedInspectorAndCompactActionsKeepBatchAndOutputIntact() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "fralo-compact-actions-\(UUID())", board = NSPasteboard.withUniqueName()
        let defaults = UserDefaults(suiteName: suite)!, store = SettingsStore(url: directory.appendingPathComponent("settings.json"))
        let controller = MainWindowController(store: store, preferences: defaults, pasteboard: board, restoreWindow: false)
        let window = try XCTUnwrap(controller.window)
        defer { window.close(); defaults.removePersistentDomain(forName: suite); board.releaseGlobally(); try? FileManager.default.removeItem(at: directory) }
        let root = try XCTUnwrap(window.contentView as? WorkbenchView), toolbar = try XCTUnwrap(window.toolbar)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        let inspector = try XCTUnwrap(root.right.body as? CompositionInspector)
        let actions = try ["copyCurrent", "exportCurrent"].map { id in
            try XCTUnwrap(toolbar.items.first { $0.itemIdentifier.rawValue == id })
        }
        let more = try XCTUnwrap(toolbar.items.first { $0.itemIdentifier.rawValue == "more" } as? NSMenuToolbarItem)
        let inspectorAction = try XCTUnwrap(toolbar.items.first { $0.itemIdentifier.rawValue == "inspector" })
        func toggleInspector() { NSApp.sendAction(try! XCTUnwrap(inspectorAction.action), to: inspectorAction.target, from: inspectorAction) }
        func copyCurrent() { let item = actions[0]; NSApp.sendAction(try! XCTUnwrap(item.action), to: item.target, from: item) }
        XCTAssertEqual(Array(toolbar.items.prefix(4).map { $0.itemIdentifier }), [.flexibleSpace, .init("sidebar"), .init("sidebarBoundary"), .init("document")])
        XCTAssertEqual(actions.map(\.action), [#selector(MainWindowController.copyCurrent(_:)), #selector(MainWindowController.exportCurrent(_:))])
        XCTAssertTrue(actions.allSatisfy { $0.target === controller && $0.isBordered })
        XCTAssertEqual(actions.map(\.label), ["复制当前图片", "导出当前图片"])
        XCTAssertFalse(actions[1].isEnabled)
        XCTAssertEqual(inspectorAction.action, #selector(MainWindowController.toggleInspector(_:)))
        XCTAssertFalse(try XCTUnwrap(toolbar.items.first { $0.itemIdentifier.rawValue == "document" }).isBordered)
        XCTAssertEqual(Array(toolbar.items.suffix(6).map(\.itemIdentifier)), [.init("copyCurrent"), .init("exportCurrent"), .space, .init("inspector"), .space, .init("more")])
        XCTAssertEqual(more.menu.items.filter { !$0.isSeparatorItem }.map(\.title), ["添加图片…", "导入文件夹…", "粘贴图片", "移除当前图片", "清空批次", "应用设置…"])
        for size in [NSSize(width: 1030, height: 640), NSSize(width: 1400, height: 1000), NSSize(width: 1900, height: 1000)] {
            window.setContentSize(size); root.layoutSubtreeIfNeeded()
            XCTAssertEqual(root.right.bounds.width, WorkbenchView.inspectorWidth, accuracy: 0.1)
            XCTAssertGreaterThan(root.content.bounds.width, 300)
        }
        XCTAssertEqual(inspectorAction.toolTip, "显示出图设置"); XCTAssertTrue(root.inspectorHidden); XCTAssertFalse(actions[0].isEnabled)
        let context = try XCTUnwrap(CGContext(data: nil, width: 300, height: 600, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0.1, green: 0.6, blue: 0.3, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 300, height: 600))
        let input = directory.appendingPathComponent("input.png"); try FrameRenderer.pngData(XCTUnwrap(context.makeImage())).write(to: input)
        controller.importURLs([input])
        let canvas = try XCTUnwrap(descendants(root.content).compactMap { $0 as? CanvasSurface }.first)
        for _ in 0..<150 where canvas.image == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(actions[0].isEnabled); XCTAssertTrue(actions[1].isEnabled)
        let image = try XCTUnwrap(canvas.image), list = try XCTUnwrap(root.left.body as? BatchList)
        inspector.mode.choose(1)
        for _ in 0..<150 where canvas.image === image { try await Task.sleep(nanoseconds: 20_000_000) }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let rendered = try XCTUnwrap(canvas.image), stored = try encoder.encode(CompositionStore(legacy: store).load())
        window.setContentSize(NSSize(width: 1030, height: 640))
        root.layoutSubtreeIfNeeded()
        let viewing = try XCTUnwrap(descendants(root.content).compactMap { $0 as? ViewToolbar }.first)
        XCTAssertTrue(viewing.isCompact)
        XCTAssertGreaterThanOrEqual(viewing.zoom.bounds.width, viewing.zoom.intrinsicContentSize.width - 1, "The fixed inspector must not truncate the zoom action at minimum width")
        let previousWidth = root.content.bounds.width
        let field = inspector.devicePicker
        XCTAssertTrue(window.makeFirstResponder(field))
        toggleInspector()
        try await Task.sleep(nanoseconds: 350_000_000); root.layoutSubtreeIfNeeded()
        XCTAssertTrue(root.inspectorHidden); XCTAssertTrue(root.right.isHidden)
        XCTAssertEqual(inspectorAction.toolTip, "显示出图设置")
        XCTAssertTrue(window.firstResponder === canvas)
        XCTAssertGreaterThan(root.content.bounds.width, previousWidth + WorkbenchView.inspectorWidth - 20)
        XCTAssertTrue(canvas.image === rendered); XCTAssertEqual(list.selectedIndex, 0)
        XCTAssertEqual(try encoder.encode(CompositionStore(legacy: store).load()), stored)
        copyCurrent()
        XCTAssertNotNil(board.data(forType: .png), "Header copy must remain connected when the inspector is hidden")
        let restored = MainWindowController(store: store, preferences: defaults, restoreWindow: false)
        defer { restored.window?.close() }
        XCTAssertTrue(try XCTUnwrap(restored.window?.contentView as? WorkbenchView).inspectorHidden)
        viewing.preview.performClick(nil)
        XCTAssertEqual(viewing.preview.state, .on); XCTAssertTrue(canvas.showsTransparencyGrid, "The floating bar toggles the transparent-bounds checkerboard")
        XCTAssertFalse(root.previewing)
        viewing.preview.performClick(nil); XCTAssertEqual(viewing.preview.state, .off)
        XCTAssertEqual(viewing.preview.accessibilityRole(), .checkBox, "VoiceOver must hear the transparency toggle's state")
        let fitted = try XCTUnwrap(canvas.zoom), backing = try XCTUnwrap(window.backingScaleFactor as CGFloat?)
        viewing.zoomIn.performClick(nil)
        let stepped = try XCTUnwrap(canvas.zoom) * backing
        XCTAssertGreaterThan(stepped, fitted * backing)
        XCTAssertTrue(MainWindowController.zoomLevels.contains { abs($0 - stepped) < 0.0001 }, "Stepping lands on a standard magnification")
        XCTAssertEqual(viewing.zoomIn.state, .off, "A step must not leave the button looking pressed")
        XCTAssertEqual(viewing.zoom.displayTitle, viewing.dimensions.stringValue, "The zoom readout is the menu's own title")
        viewing.zoomOut.performClick(nil)
        XCTAssertLessThan(try XCTUnwrap(canvas.zoom) * backing, stepped)
        for _ in 0..<20 { viewing.zoomOut.performClick(nil) }
        XCTAssertFalse(viewing.zoomOut.isEnabled, "The smallest magnification disables zoom out")
        XCTAssertNil(viewing.zoom.selectedItem, "A stepped zoom between presets must not keep the fit checkmark")
        controller.fitPreview(nil); XCTAssertEqual(viewing.zoom.indexOfSelectedItem, 0); XCTAssertTrue(viewing.zoomOut.isEnabled)
        controller.togglePreview(nil)
        XCTAssertTrue(root.previewing); XCTAssertEqual(inspectorAction.toolTip, "显示出图设置")
        XCTAssertTrue(toolbar.items.contains { $0.itemIdentifier.rawValue == "add" }, "Previewing hides the list, so the toolbar offers “+”")
        toggleInspector()
        try await Task.sleep(nanoseconds: 350_000_000); root.layoutSubtreeIfNeeded()
        XCTAssertFalse(root.previewing); XCTAssertFalse(root.inspectorHidden); XCTAssertFalse(root.right.isHidden)
        XCTAssertEqual(inspectorAction.toolTip, "隐藏出图设置")
        XCTAssertFalse(toolbar.items.contains { $0.itemIdentifier.rawValue == "add" }, "The list header owns “+” while the list is visible")
        XCTAssertNotNil(toolbar.items.first { $0 is NSTrackingSeparatorToolbarItem })
        XCTAssertEqual(root.right.bounds.width, WorkbenchView.inspectorWidth, accuracy: 0.1)
        window.setContentSize(NSSize(width: 1900, height: 1000)); root.layoutSubtreeIfNeeded()
        // Native split/stack layout finishes on the run loop after a window resize.
        for _ in 0..<20 where viewing.isCompact {
            try await Task.sleep(nanoseconds: 20_000_000); root.layoutSubtreeIfNeeded()
        }
        XCTAssertFalse(viewing.isCompact, "A wide preview viewport must restore the regular toolbar spacing")
    }


    @MainActor func testDockedSidebarUsesLeadingNativeToggleAndRestoresCollapsedState() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "fralo-docked-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(url: directory.appendingPathComponent("settings.json"))
        let controller = MainWindowController(store: store, preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window); defer { window.close() }
        let root = try XCTUnwrap(window.contentView as? WorkbenchView)
        let toggle = try XCTUnwrap(window.toolbar?.items.first { $0.itemIdentifier.rawValue == "sidebar" })
        let boundary = try XCTUnwrap(window.toolbar?.items.first { $0 is NSTrackingSeparatorToolbarItem } as? NSTrackingSeparatorToolbarItem)
        XCTAssertTrue(boundary.splitView === root.splitView)
        XCTAssertEqual(boundary.dividerIndex, 0)
        XCTAssertTrue((window.contentViewController as? NSSplitViewController)?.splitView === root.splitView)
        XCTAssertEqual(toggle.action, #selector(MainWindowController.toggleSidebar(_:)))
        toggle.validate()
        XCTAssertTrue(toggle.isEnabled, "The native navigation item must validate against the workbench controller")
        XCTAssertEqual(toggle.visibilityPriority, .user)
        for size in [NSSize(width: 1030, height: 640), NSSize(width: 1400, height: 1000)] {
            window.setContentSize(size); root.layoutSubtreeIfNeeded()
            XCTAssertEqual(root.left.frame.origin, .zero)
            XCTAssertEqual(root.left.frame.height, root.bounds.height)
            XCTAssertGreaterThanOrEqual(root.left.frame.width, 230)
            XCTAssertGreaterThan(root.content.frame.width, 300)
            XCTAssertEqual(root.left.layer?.shadowOpacity ?? 0, 0)
            let header = try XCTUnwrap(descendants(root.left).compactMap { $0 as? NSStackView }.first)
            XCTAssertGreaterThanOrEqual(header.convert(header.bounds, to: root).minY, root.safeAreaInsets.top)
        }
        controller.toggleInspector(nil) // Explicitly open settings for this focus-preservation test.
        let inspector = try XCTUnwrap(root.right.body as? CompositionInspector)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        let field = inspector.devicePicker
        XCTAssertTrue(window.makeFirstResponder(field))
        let responder = window.firstResponder
        controller.toggleSidebar(nil)
        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertTrue(window.firstResponder === responder, "Hiding the list must not steal an inspector editing session")
        XCTAssertTrue(root.sidebarItem.isCollapsed)
        XCTAssertEqual(window.toolbar?.items.first?.itemIdentifier.rawValue, "add")
        XCTAssertFalse(window.toolbar?.items.contains { $0 is NSTrackingSeparatorToolbarItem } ?? true)
        let restored = MainWindowController(store: store, preferences: defaults, restoreWindow: false)
        defer { restored.window?.close() }
        XCTAssertTrue(try XCTUnwrap(restored.window?.contentView as? WorkbenchView).collapsed)
        controller.toggleSidebar(nil); controller.toggleSidebar(nil); controller.toggleSidebar(nil)
        try await Task.sleep(nanoseconds: 350_000_000); root.layoutSubtreeIfNeeded()
        XCTAssertFalse(root.collapsed); XCTAssertFalse(root.sidebarItem.isCollapsed)
        XCTAssertEqual(window.toolbar?.items.first?.itemIdentifier, .flexibleSpace)
        XCTAssertEqual(window.toolbar?.items.filter { $0 is NSTrackingSeparatorToolbarItem }.count, 1)
        XCTAssertEqual(root.left.frame.minX, 0)
    }


    @MainActor func testNativeHeaderAndShadowChangesKeepThePreviewScaleStable() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "fralo-header-shadow-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")), preferences: defaults, restoreWindow: false)
        defer { controller.window?.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let window = try XCTUnwrap(controller.window)
        XCTAssertEqual(window.titleVisibility, .hidden); XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titlebarSeparatorStyle, .none)
        XCTAssertEqual(window.toolbarStyle, .unified)
        window.setContentSize(NSSize(width: 1400, height: 1000))
        let root = try XCTUnwrap(window.contentView as? WorkbenchView)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        let shadow = try XCTUnwrap(descendants(root).compactMap { $0 as? ValuePicker }.first { $0.accessibilityLabel() == "阴影" })
        let canvas = try XCTUnwrap(descendants(root).compactMap { $0 as? CanvasSurface }.first)
        let context = try XCTUnwrap(CGContext(data: nil, width: 400, height: 800, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0.1, green: 0.4, blue: 0.3, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 400, height: 800))
        let file = directory.appendingPathComponent("shadow.png"); try FrameRenderer.pngData(XCTUnwrap(context.makeImage())).write(to: file)
        controller.importURLs([file])
        for _ in 0..<150 where canvas.image == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        root.layoutSubtreeIfNeeded()
        let initial = try XCTUnwrap(canvas.zoom)
        for index in [1, 2, 0] {
            let previous = canvas.image; shadow.choose(index)
            for _ in 0..<150 where canvas.image === previous { try await Task.sleep(nanoseconds: 20_000_000) }
            root.layoutSubtreeIfNeeded()
            XCTAssertEqual(try XCTUnwrap(canvas.zoom), initial, accuracy: 0.0001, "Shadow padding must not rescale the device in fit-to-window preview")
        }
    }

    @MainActor func testChangingSourceKeepsDevicePreviewSizeAndChosenZoom() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "fralo-fixed-preview-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let board = NSPasteboard.withUniqueName()
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")), preferences: defaults, pasteboard: board, restoreWindow: false)
        let window = try XCTUnwrap(controller.window)
        defer { window.close(); defaults.removePersistentDomain(forName: suite); board.releaseGlobally(); try? FileManager.default.removeItem(at: directory) }
        window.setContentSize(NSSize(width: 1400, height: 1000))
        let root = try XCTUnwrap(window.contentView as? WorkbenchView)
        let inspector = try XCTUnwrap(root.right.body as? CompositionInspector), list = try XCTUnwrap(root.left.body as? BatchList)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        let canvas = try XCTUnwrap(descendants(root).compactMap { $0 as? CanvasSurface }.first)
        let viewing = try XCTUnwrap(descendants(root).compactMap { $0 as? ViewToolbar }.first)
        let sizes = [CGSize(width: 80, height: 20), CGSize(width: 1600, height: 400), CGSize(width: 100, height: 240)]
        let files = try sizes.enumerated().map { index, size -> URL in
            let context = try XCTUnwrap(CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(srgbRed: 0.2, green: 0.5, blue: 0.3, alpha: 1)); context.fill(CGRect(origin: .zero, size: size))
            let file = directory.appendingPathComponent("source-\(index).png")
            try FrameRenderer.pngData(XCTUnwrap(context.makeImage())).write(to: file); return file
        }
        func waitForPreview(replacing previous: NSImage?) async throws {
            for _ in 0..<300 where canvas.image == nil || canvas.image === previous { try await Task.sleep(nanoseconds: 20_000_000) }
            XCTAssertNotNil(canvas.image); XCTAssertFalse(canvas.image === previous)
            root.layoutSubtreeIfNeeded()
        }
        controller.importURLs(files); try await waitForPreview(replacing: nil)
        for device in 0..<3 {
            if device > 0 {
                let previous = canvas.image; inspector.devicePicker.choose(device); try await waitForPreview(replacing: previous)
            }
            controller.fitPreview(nil); root.layoutSubtreeIfNeeded()
            let size = try XCTUnwrap(canvas.image).size, fitRect = canvas.imageRect, fitZoom = try XCTUnwrap(canvas.zoom)
            for index in [1, 2, 0] {
                let previous = canvas.image; list.select(index); try await waitForPreview(replacing: previous)
                XCTAssertEqual(try XCTUnwrap(canvas.image).size, size)
                XCTAssertEqual(try XCTUnwrap(canvas.zoom), fitZoom, accuracy: 0.0001)
                XCTAssertEqual(canvas.imageRect, fitRect)
                XCTAssertTrue(viewing.dimensions.stringValue.hasSuffix("%"), "The floating bar shows the zoom; pixel size lives in the inspector footer")
                XCTAssertEqual(viewing.dimensions.toolTip, "\(Int(size.width)) × \(Int(size.height)) px")
            }
            controller.actualPixels(nil); root.layoutSubtreeIfNeeded()
            let actualZoom = try XCTUnwrap(canvas.zoom), actualRect = canvas.imageRect
            let previous = canvas.image; list.select(1); try await waitForPreview(replacing: previous)
            XCTAssertEqual(try XCTUnwrap(canvas.zoom), actualZoom, accuracy: 0.0001, "Changing source must preserve the chosen pixel zoom")
            XCTAssertEqual(canvas.imageRect, actualRect)
            controller.copyCurrent(nil)
            let copied = try XCTUnwrap(board.data(forType: .png))
            XCTAssertEqual(try ImageInput(data: copied, name: "copy.png").dimensions(), size)
            let beforeReset = canvas.image; list.select(0); try await waitForPreview(replacing: beforeReset)
        }
    }

    @MainActor func testInspectorWidthStaysFixedWhenLongSettingsNeedScrolling() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "fralo-scroll-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")), preferences: defaults, restoreWindow: false)
        defer { controller.window?.close(); try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: suite) }
        let window = try XCTUnwrap(controller.window), root = try XCTUnwrap(window.contentView as? WorkbenchView)
        let inspector = try XCTUnwrap(root.right.body as? CompositionInspector)
        let scroll = try XCTUnwrap(inspector.subviews.first as? NSScrollView)
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertTrue(inspector.exportSettings.isDescendant(of: document), "Export format and JPEG parameters must scroll with the other settings")
        XCTAssertFalse(inspector.outputInfo.isDescendant(of: document), "Output size stays in the fixed footer above the export action")
        XCTAssertTrue(inspector.outputInfo.isDescendant(of: root.right))
        XCTAssertFalse(inspector.mode.isDescendant(of: document), "The mode selector stays pinned above the scrolling form")
        // Reproduce the user's always-visible native scrollbar preference without changing the OS.
        scroll.scrollerStyle = .legacy
        window.setContentSize(NSSize(width: 1400, height: 1000)); root.layoutSubtreeIfNeeded()
        let before = inspector.devicePicker.convert(inspector.devicePicker.bounds, to: root.right)
        let clipWidth = scroll.contentView.bounds.width
        inspector.mode.choose(1); root.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 60_000_000); root.layoutSubtreeIfNeeded()
        let after = inspector.devicePicker.convert(inspector.devicePicker.bounds, to: root.right)
        XCTAssertEqual(after.width, before.width, accuracy: 0.5, "Overflow must not squeeze the settings")
        XCTAssertEqual(after.midX, before.midX, accuracy: 0.5, "Switching mode must not shift controls sideways")
        XCTAssertEqual(scroll.contentView.bounds.width, clipWidth, accuracy: 0.5)
    }

    @MainActor func testPreviewActivityBelongsToTheViewingToolbar() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "fralo-preview-activity-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")), preferences: defaults, restoreWindow: false)
        defer { controller.window?.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        let root = try XCTUnwrap(controller.window?.contentView)
        let toolbar = try XCTUnwrap(descendants(root).compactMap { $0 as? ViewToolbar }.first)
        let activity = descendants(root).compactMap { $0 as? NSProgressIndicator }.filter { !($0.superview is ActionButton) }
        XCTAssertEqual(activity.count, 1)
        for spinner in activity { XCTAssertTrue(spinner.isDescendant(of: toolbar), "Preview activity needs a stable place beside preview controls") }
    }
    @MainActor func testSwitchingBatchInputKeepsTheFixedOrientationIllustration() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "fralo-fixed-demo-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")), preferences: defaults, restoreWindow: false)
        defer { controller.window?.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        let root = try XCTUnwrap(controller.window?.contentView as? WorkbenchView)
        let list = try XCTUnwrap(root.left.body as? BatchList)
        let choice = try XCTUnwrap(descendants(root.right.body).compactMap { $0 as? VisualChoiceGroup }.first { $0.accessibilityLabel() == "方向" })
        let canvas = try XCTUnwrap(descendants(root.content).compactMap { $0 as? CanvasSurface }.first)
        for (name, red, green) in [("green.png", 0.1, 0.8), ("red.png", 0.9, 0.1)] {
            let context = try XCTUnwrap(CGContext(data: nil, width: 100, height: 200, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(srgbRed: red, green: green, blue: 0.1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
            try FrameRenderer.pngData(XCTUnwrap(context.makeImage())).write(to: directory.appendingPathComponent(name))
        }
        controller.importURLs([directory.appendingPathComponent("green.png"), directory.appendingPathComponent("red.png")])
        for _ in 0..<150 where canvas.image == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        let first = try XCTUnwrap(canvas.image)
        root.layoutSubtreeIfNeeded()
        func illustration() throws -> Data {
            let bitmap = try XCTUnwrap(choice.bitmapImageRepForCachingDisplay(in: choice.bounds))
            choice.cacheDisplay(in: choice.bounds, to: bitmap)
            return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        }
        let before = try illustration()
        list.select(1)
        let deadline = Date(timeIntervalSinceNow: 1.5)
        while canvas.image === first && Date() < deadline {
            RunLoop.current.run(mode: .eventTracking, before: Date(timeIntervalSinceNow: 0.02))
        }
        XCTAssertFalse(canvas.image === first, "The canvas must update while a contextual menu is tracking, before it closes")
        for _ in 0..<150 where canvas.image === first { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertFalse(canvas.image === first, "The real preview still follows the selected input")
        XCTAssertEqual(try illustration(), before, "The inspector demo must not follow the selected input")
        let inspector = try XCTUnwrap(root.right.body as? CompositionInspector)
        for _ in 0..<150 where !inspector.outputSize.stringValue.hasPrefix("约 ") { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(inspector.outputSize.stringValue.hasSuffix(" / 张"), "The per-image size is estimated automatically after each preview")
        let compression = try XCTUnwrap(descendants(inspector).compactMap { $0 as? ValuePicker }.first { $0.accessibilityLabel() == "PNG 体积" })
        let previous = canvas.image; compression.choose(1)
        for _ in 0..<250 where canvas.image === previous { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertFalse(inspector.settings.pngLossless)
        XCTAssertFalse(canvas.image === previous)
        XCTAssertTrue(inspector.outputSize.stringValue.hasPrefix("约 "), "Reuse PNG preview encoding to report bytes without another render")
    }

}
