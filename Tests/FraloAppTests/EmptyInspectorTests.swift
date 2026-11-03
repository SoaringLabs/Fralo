import FraloLocalization
import AppKit
import XCTest
import FraloCore
import FraloDesignSystem
@testable import FraloApp

final class EmptyInspectorTests: XCTestCase {
    private var fixture: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/FraloApp/Development/Fixtures/03-journal.png")
    }

    @MainActor func testEmptyBrowserPageKeepsThePopulatedWindowCorners() throws {
        _ = NSApplication.shared
        let stage = EmptyStageView(action: ActionButton("Add", role: .primary))
        stage.showEmpty(title: "Drop screenshots", detail: "PNG / JPEG")
        for browser in BrowserStyle.allCases {
            for appearance in BrowserAppearance.allCases {
                var settings = CompositionSettings(); settings.display = .browser
                settings.browser = browser; settings.browserAppearance = appearance; settings.transparentShadow = .none
                let rendered = try CompositionRenderer.render(ImageInput(url: fixture), settings: settings, maxDimension: 1200)
                let layout = try CompositionRenderer.screenLayout(settings)
                stage.device = .init(image: NSImage(cgImage: rendered.image, size: NSSize(width: rendered.image.width, height: rendered.image.height)),
                                     screen: layout.rect, cornerRadius: layout.cornerRadius, display: .browser,
                                     orientation: .portrait, browserAppearance: appearance)
                for size in [NSSize(width: 900, height: 700), NSSize(width: 1200, height: 900)] {
                    stage.setFrameSize(size); stage.layoutSubtreeIfNeeded()
                    let context = try XCTUnwrap(CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                    context.translateBy(x: 0, y: size.height); context.scaleBy(x: 1, y: -1)
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
                    stage.draw(stage.bounds)
                    NSGraphicsContext.restoreGraphicsState()
                    let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
                    let frame = try XCTUnwrap(stage.deviceRect), screen = try XCTUnwrap(stage.screenRect)
                    func alpha(_ x: CGFloat, _ y: CGFloat) -> UInt8 {
                        bytes[Int(y) * context.bytesPerRow + Int(x) * 4 + 3]
                    }
                    let name = "\(browser)/\(appearance)/\(size)"
                    for x in [frame.minX + 1, frame.maxX - 2] {
                        // The contact shadow may remain, but the blank page must not fill the corner.
                        XCTAssertLessThan(alpha(x, frame.maxY - 2), 180, name)
                        XCTAssertEqual(alpha(x, screen.minY + 2), 255, "The upper content seam remains square: \(name)")
                    }
                    XCTAssertEqual(alpha(frame.midX, frame.maxY - 2), 255, name)
                }
            }
        }
    }

    @MainActor func testGuidanceCentersOnPhoneScreenButKeepsOtherTargetsAndIslandMargins() throws {
        _ = NSApplication.shared
        let stage = EmptyStageView(action: ActionButton("Add", role: .primary))
        let content = try XCTUnwrap(stage.zone.subviews.compactMap { $0 as? NSStackView }.first)
        stage.showEmpty(title: "Drop screenshots", detail: "PNG / JPEG")
        for size in [NSSize(width: 1030, height: 640), NSSize(width: 1400, height: 950)] {
            stage.setFrameSize(size)
            stage.showEmpty(title: "Drop screenshots", detail: "PNG / JPEG")
            // Reuse one stage to catch stale phone offsets when switching targets.
            for (display, orientation) in [(DisplayKind.phone, Orientation.portrait), (.tablet, .portrait),
                                            (.phone, .landscape), (.browser, .landscape)] {
                let imageSize = orientation == .portrait ? NSSize(width: 400, height: 800) : NSSize(width: 800, height: 400)
                stage.device = .init(image: NSImage(size: imageSize), screen: CGRect(x: 0.03, y: 0.03, width: 0.94, height: 0.94),
                                     cornerRadius: 0.05, display: display, orientation: orientation)
                stage.layoutSubtreeIfNeeded()
                let screen = try XCTUnwrap(stage.screenRect), zone = stage.zone.frame
                let expected = display == .phone ? screen : zone
                for feedback in [false, true, false] {
                    if feedback { stage.showDrag(.accepting, title: "Release to add", detail: "iPhone · Portrait") }
                    else { stage.showEmpty(title: "Drop screenshots", detail: "PNG / JPEG") }
                    stage.layoutSubtreeIfNeeded()
                    let drawnContent = stage.convert(content.bounds, from: content)
                    XCTAssertEqual(drawnContent.midX, expected.midX, accuracy: 1, "\(display) \(orientation) horizontal center")
                    XCTAssertEqual(drawnContent.midY, expected.midY, accuracy: 1, "\(display) \(orientation) vertical center")
                    XCTAssertEqual(stage.zone.frame, zone, "Changing feedback must not move the border")
                }
                if display == .phone, orientation == .portrait {
                    XCTAssertGreaterThan(zone.minY - screen.minY, screen.maxY - zone.maxY, "The border still clears the top island")
                } else if display == .phone {
                    XCTAssertGreaterThan(screen.maxX - zone.maxX, zone.minX - screen.minX, "The border still clears the side island")
                } else {
                    XCTAssertEqual(zone.midX, screen.midX, accuracy: 1)
                    XCTAssertEqual(zone.midY, screen.midY, accuracy: 1)
                }
            }
            stage.showError("Cannot render")
            stage.layoutSubtreeIfNeeded()
            let fallback = stage.convert(content.bounds, from: content)
            XCTAssertEqual(fallback.midX, stage.zone.frame.midX, accuracy: 1)
            XCTAssertEqual(fallback.midY, stage.zone.frame.midY, accuracy: 1)
        }
    }

    @MainActor func testEmptyBatchCollapsesOnlyTheListAndKeepsTheInspector() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "fralo-empty-panels-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")), preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window)
        defer { window.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let root = try XCTUnwrap(window.contentView as? WorkbenchView)
        let list = try XCTUnwrap(root.left.body as? BatchList)
        let source = fixture
        XCTAssertTrue(root.collapsed); XCTAssertFalse(root.inspectorHidden); XCTAssertFalse(root.right.isHidden)
        XCTAssertFalse(defaults.bool(forKey: "sidebarCollapsed"), "Automatic collapse must not overwrite the user's preference")
        controller.importURLs([source]); XCTAssertFalse(root.collapsed); XCTAssertFalse(root.inspectorHidden)
        controller.newBatch(nil); XCTAssertTrue(list.entries.isEmpty); XCTAssertTrue(root.collapsed); XCTAssertFalse(root.inspectorHidden)
        XCTAssertFalse(defaults.bool(forKey: "sidebarCollapsed"))
        controller.undoChange(nil); XCTAssertEqual(list.entries.count, 1); XCTAssertFalse(root.collapsed)
        controller.redoChange(nil); XCTAssertTrue(list.entries.isEmpty); XCTAssertTrue(root.collapsed)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let second = directory.appendingPathComponent("second.png")
        try FileManager.default.copyItem(at: source, to: second)
        controller.importURLs([source, second]); XCTAssertFalse(root.collapsed)
        controller.removeSelected(nil); XCTAssertEqual(list.entries.count, 1); XCTAssertFalse(root.collapsed)
        controller.removeSelected(nil); XCTAssertTrue(list.entries.isEmpty); XCTAssertTrue(root.collapsed)
        XCTAssertTrue((window.firstResponder as? NSView)?.isHiddenOrHasHiddenAncestor == false)
        controller.undoChange(nil); XCTAssertFalse(root.collapsed)
        controller.toggleSidebar(nil); XCTAssertTrue(root.collapsed)
        XCTAssertTrue(defaults.bool(forKey: "sidebarCollapsed"))
        controller.newBatch(nil); controller.undoChange(nil)
        XCTAssertTrue(root.collapsed, "Restoring content must retain an explicitly hidden list")
    }

    @MainActor func testOpeningTheEmptyListShowsItsPlaceholderAndSurvivesImports() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "fralo-empty-placeholder-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")), preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window)
        defer { window.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let root = try XCTUnwrap(window.contentView as? WorkbenchView)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        let placeholder = try XCTUnwrap(descendants(root.left).compactMap { $0 as? SidebarEmptyPlaceholder }.first)
        controller.toggleSidebar(nil)
        XCTAssertFalse(root.collapsed); XCTAssertFalse(placeholder.isHidden); XCTAssertTrue(root.left.body.isHidden)
        controller.newBatch(nil)
        XCTAssertFalse(root.collapsed, "Repeated empty updates must not undo an explicit Show List command")
        controller.importURLs([fixture]); XCTAssertTrue(placeholder.isHidden); XCTAssertFalse(root.left.body.isHidden)
        controller.newBatch(nil); XCTAssertTrue(root.collapsed); XCTAssertFalse(placeholder.isHidden)
        XCTAssertEqual(window.subtitle, "iPhone 18 Pro Max · " + L10n.tr("竖屏") + " · " + L10n.tr("透明 PNG"), "The empty subtitle names what the first import will be framed as")
    }

    @MainActor func testDropSummaryCountsFolderImagesAndDeclinesUnsupportedOrDuplicateFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = directory.appendingPathComponent("a.png"), other = directory.appendingPathComponent("b.jpg")
        let pdf = directory.appendingPathComponent("notes.pdf")
        for url in [image, other, pdf] { try Data([0]).write(to: url) }
        let folder = DropSummary(urls: [directory])
        XCTAssertEqual(folder.images, 2); XCTAssertEqual(folder.accepted, [directory]); XCTAssertTrue(folder.canDrop)
        XCTAssertEqual(folder.message(appending: false, device: "iPhone 18 Pro · 竖屏").title, L10n.tr("松开以添加 \(2) 张图片"))
        let mixed = DropSummary(urls: [image, pdf])
        XCTAssertEqual(mixed.accepted, [image]); XCTAssertEqual(mixed.message(appending: true, device: "").detail, L10n.tr("将添加 \(1) 张 · 忽略 \(1) 个文件"))
        XCTAssertEqual(mixed.message(appending: true, device: "").title, L10n.tr("松开以追加 \(1) 张图片到批次"))
        let unsupported = DropSummary(urls: [pdf])
        XCTAssertFalse(unsupported.canDrop)
        XCTAssertEqual(unsupported.message(appending: false, device: "").title, L10n.tr("无法添加这个文件"))
        XCTAssertEqual(unsupported.message(appending: false, device: "").detail, L10n.tr("仅支持 PNG / JPEG 图片"))
        let duplicate = DropSummary(urls: [image], existing: [ImageInput(url: image).id])
        XCTAssertFalse(duplicate.canDrop); XCTAssertEqual(duplicate.message(appending: true, device: "").title, L10n.tr("这些图片已在批次中"))
    }

    @MainActor func testEmptyStageDrawsTheSelectedFrameAndPlacesTheTargetOnItsScreen() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "fralo-empty-frame-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")), preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window)
        defer { window.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let root = try XCTUnwrap(window.contentView as? WorkbenchView)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        let stage = try XCTUnwrap(descendants(root.content).compactMap { $0 as? EmptyStageView }.first)
        let inspector = try XCTUnwrap(root.right.body as? CompositionInspector)
        for size in [NSSize(width: 1030, height: 640), NSSize(width: 1400, height: 950)] {
            window.setContentSize(size); root.layoutSubtreeIfNeeded()
            for _ in 0..<150 where stage.device == nil { try await Task.sleep(nanoseconds: 20_000_000) }
            stage.layoutSubtreeIfNeeded()
            let frame = try XCTUnwrap(stage.deviceRect), screen = try XCTUnwrap(stage.screenRect)
            XCTAssertTrue(frame.contains(screen)); XCTAssertTrue(screen.contains(stage.zone.frame))
            XCTAssertLessThanOrEqual(frame.maxX, stage.bounds.width - root.viewingInsets.right + 0.5, "The frame stays clear of the inspector")
            XCTAssertGreaterThanOrEqual(frame.minY, root.headerHeight, "The frame stays below the header")
            XCTAssertFalse(stage.zone.action.isHiddenOrHasHiddenAncestor)
            XCTAssertTrue(stage.zone.bounds.contains(stage.zone.convert(stage.zone.action.frame, from: stage.zone.action.superview)))
        }
        let portrait = try XCTUnwrap(stage.device?.image.size)
        var landscape = inspector.settings; landscape.orientation = .landscape
        inspector.restore(landscape); inspector.onChange?(landscape)
        for _ in 0..<150 where stage.device?.image.size == portrait { try await Task.sleep(nanoseconds: 20_000_000) }
        let turned = try XCTUnwrap(stage.device?.image.size)
        XCTAssertGreaterThan(turned.width, turned.height, "The empty frame follows the selected orientation")
    }
}
