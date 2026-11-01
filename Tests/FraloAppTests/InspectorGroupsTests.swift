import AppKit
import XCTest
import FraloCore
import FraloDesignSystem
@testable import FraloApp

final class InspectorGroupsTests: XCTestCase {
    @MainActor private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
    @MainActor private func visible<T: NSView>(_ type: T.Type, in inspector: CompositionInspector) -> [T] {
        descendants(inspector).compactMap { $0 as? T }.filter { !$0.isHiddenOrHasHiddenAncestor }
    }
    @MainActor private func titles(_ inspector: CompositionInspector) -> [String] {
        let groups: Set<String> = ["设备", "外观", "构图", "背景", "导出"]
        return visible(NSTextField.self, in: inspector).map(\.stringValue).filter(groups.contains)
    }
    @MainActor private func texts(_ inspector: CompositionInspector) -> [String] { visible(NSTextField.self, in: inspector).map(\.stringValue) }
    @MainActor private func slider(_ label: String, _ inspector: CompositionInspector) -> CompactSliderField? {
        visible(CompactSliderField.self, in: inspector).first { $0.slider.accessibilityLabel() == label }
    }

    @MainActor func testTransparentModeShowsOnlyDeviceAppearanceAndFixedPNGExport() throws {
        _ = NSApplication.shared
        var settings = CompositionSettings(); settings.format = .jpeg; settings.deviceOpacity = 0.4
        let inspector = CompositionInspector(settings: settings)
        XCTAssertEqual(titles(inspector), ["设备", "外观", "导出"])
        XCTAssertEqual(inspector.mode.accessibilityLabel(), "成品背景")
        XCTAssertTrue(texts(inspector).contains("PNG（保留透明）"))
        XCTAssertTrue(inspector.formatPicker.isHiddenOrHasHiddenAncestor || inspector.formatPicker.superview == nil)
        XCTAssertNil(slider("不透明度", inspector), "Transparent output is always opaque")
        XCTAssertNil(slider("画质", inspector), "JPEG settings never apply to transparent output")
        XCTAssertNotNil(visible(ValuePicker.self, in: inspector).first { $0.accessibilityLabel() == "文件大小" })
        XCTAssertFalse(texts(inspector).contains { $0.contains("iPhone 18") }, "Group titles carry no device summary")
    }

    @MainActor func testBackgroundModeAddsCompositionAndBackgroundBetweenStableGroups() throws {
        _ = NSApplication.shared
        let inspector = CompositionInspector(settings: CompositionSettings())
        inspector.mode.choose(1)
        XCTAssertEqual(titles(inspector), ["设备", "外观", "构图", "背景", "导出"])
        XCTAssertNotNil(slider("不透明度", inspector))
        XCTAssertNotNil(slider("设备大小", inspector))
        XCTAssertFalse(descendants(inspector).contains { $0.accessibilityLabel() == "套用模板" }, "Templates were removed")
        let canvas = try XCTUnwrap(visible(ChoiceMenu.self, in: inspector).first { $0.accessibilityLabel() == "画布比例" })
        XCTAssertEqual(canvas.titleOfSelectedItem, "4:3 横向")
        XCTAssertTrue(texts(inspector).contains("在预览中拖动空白处调整背景"), "Image backgrounds explain dragging empty canvas")
        XCTAssertFalse(descendants(inspector).contains { $0.accessibilityLabel() == "拖动调整背景" }, "No drag-target switch")
        XCTAssertFalse(inspector.formatPicker.isHiddenOrHasHiddenAncestor)
        inspector.formatPicker.choose(1)
        XCTAssertNotNil(slider("画质", inspector))
        XCTAssertFalse(descendants(inspector).contains { $0.accessibilityLabel()?.contains("填色") == true })
        inspector.mode.choose(0)
        XCTAssertEqual(titles(inspector), ["设备", "外观", "导出"])
        XCTAssertEqual(inspector.settings.format, .jpeg, "The JPEG choice is kept for the next background export")
        XCTAssertNil(slider("画质", inspector))
    }

    @MainActor func testDeviceSizeSnapsToFullCanvasAndWarnsPastIt() throws {
        _ = NSApplication.shared
        var settings = CompositionSettings(); settings.mode = .background
        let inspector = CompositionInspector(settings: settings)
        let size = try XCTUnwrap(slider("设备大小", inspector))
        XCTAssertEqual(size.slider.markValue, 100)
        XCTAssertEqual(size.slider.accessibilityValueDescription(), "占画布 74%")
        XCTAssertFalse(texts(inspector).contains("超出画布的部分会被裁掉"))
        size.slider.doubleValue = 97; size.slider.sendAction(size.slider.action, to: size.slider.target)
        XCTAssertEqual(inspector.settings.deviceScale, 1, "Close to 100% settles on exactly 100%")
        XCTAssertFalse(texts(inspector).contains("超出画布的部分会被裁掉"))
        size.slider.doubleValue = 120; size.slider.sendAction(size.slider.action, to: size.slider.target)
        XCTAssertEqual(inspector.settings.deviceScale, 1.2, accuracy: 0.0001)
        XCTAssertTrue(texts(inspector).contains("超出画布的部分会被裁掉"))
        size.slider.doubleValue = 90; size.slider.sendAction(size.slider.action, to: size.slider.target)
        XCTAssertEqual(inspector.settings.deviceScale, 0.9, accuracy: 0.0001)
        XCTAssertFalse(texts(inspector).contains("超出画布的部分会被裁掉"))
    }

    @MainActor func testCustomImageIsAFourthTileThatStaysAfterTryingAPreset() throws {
        _ = NSApplication.shared
        var settings = CompositionSettings(); settings.mode = .background
        var inspector = CompositionInspector(settings: settings)
        func tiles() throws -> VisualChoiceGroup { try XCTUnwrap(visible(VisualChoiceGroup.self, in: inspector).first { $0.accessibilityLabel() == "背景图片" }) }
        XCTAssertEqual(try tiles().accessibilityChildren()?.count, 4)
        try tiles().choose(3)
        XCTAssertEqual(inspector.settings.background, .warm, "Without an image the custom tile only offers to add one")
        XCTAssertEqual(try tiles().selectedIndex, 0)

        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FraloApp/Development/Fixtures/03-journal.png")
        settings.localBackgroundPath = fixture.path; settings.background = .local
        inspector = CompositionInspector(settings: settings)
        XCTAssertEqual(try tiles().selectedIndex, 3)
        XCTAssertTrue(texts(inspector).contains("03-journal.png"))
        XCTAssertTrue(visible(NSButton.self, in: inspector).contains { $0.title == "更换…" })
        try tiles().choose(1)
        XCTAssertEqual(inspector.settings.background, .mist)
        XCTAssertEqual(inspector.settings.localBackgroundPath, fixture.path)
        XCTAssertFalse(texts(inspector).contains("03-journal.png"), "The file row appears only while the custom image is chosen")
        try tiles().choose(3)
        XCTAssertEqual(inspector.settings.background, .local, "Switching back needs no new upload")
        XCTAssertEqual(inspector.settings.backgroundScale, 1)
    }

    @MainActor func testChoosingATileRebuildsWithoutAKeyboardFocusRing() throws {
        _ = NSApplication.shared
        var settings = CompositionSettings(); settings.mode = .background
        let inspector = CompositionInspector(settings: settings)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 1100), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        window.contentView = inspector; inspector.layoutSubtreeIfNeeded()
        func tiles() throws -> VisualChoiceGroup { try XCTUnwrap(visible(VisualChoiceGroup.self, in: inspector).first { $0.accessibilityLabel() == "背景图片" }) }
        let first = try tiles()
        window.makeFirstResponder(first); first.choose(2)
        let rebuilt = try tiles()
        XCTAssertFalse(rebuilt === first, "Choosing a tile rebuilds the background group")
        XCTAssertTrue(window.firstResponder === rebuilt, "Focus moves to the rebuilt group")
        XCTAssertEqual(rebuilt.focusRingType, .none, "Focus restored after a click must not draw the keyboard ring")
    }

    @MainActor func testValueChoicesSitOneSizeBelowCategoryTabs() throws {
        _ = NSApplication.shared
        var settings = CompositionSettings(); settings.mode = .background; settings.display = .browser
        let inspector = CompositionInspector(settings: settings)
        let pickers = visible(ValuePicker.self, in: inspector)
        let tabs = Set(["成品背景", "设备类型"])
        for picker in pickers {
            XCTAssertEqual(picker.controlSize, tabs.contains(picker.accessibilityLabel() ?? "") ? .large : .regular, picker.accessibilityLabel() ?? "")
        }
        XCTAssertEqual(Set(pickers.compactMap { $0.accessibilityLabel() }), ["设备类型", "配色", "阴影", "背景类型", "文件格式", "文件大小"], "The mode switch lives above the scrolling groups")
        XCTAssertEqual(inspector.mode.controlSize, .large)
    }

    @MainActor func testGradientOffersStartAndEndColors() throws {
        _ = NSApplication.shared
        var settings = CompositionSettings(); settings.mode = .background; settings.background = .gradient
        let inspector = CompositionInspector(settings: settings)
        let wells = visible(ColorChoice.self, in: inspector).compactMap { $0.accessibilityLabel() }
        XCTAssertEqual(wells, ["起点颜色", "终点颜色"])
        XCTAssertNotNil(slider("不透明度", inspector))
        XCTAssertNil(slider("背景透明度", inspector))
    }
}
