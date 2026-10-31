import AppKit
import XCTest
import FraloCore
import FraloDesignSystem
@testable import FraloApp

final class BrowserAppearanceTests: XCTestCase {
    @MainActor private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
    @MainActor private func picker(_ inspector: CompositionInspector) -> ValuePicker? {
        descendants(inspector).compactMap { $0 as? ValuePicker }.first { $0.accessibilityLabel() == "浏览器配色" }
    }

    @MainActor func testBrowserPickerKeyboardAndDisabledStatePreserveSelectionAcrossDevices() throws {
        _ = NSApplication.shared
        let inspector = CompositionInspector(settings: CompositionSettings())
        XCTAssertNil(picker(inspector))
        inspector.devicePicker.choose(2)
        let control = try XCTUnwrap(picker(inspector))
        XCTAssertEqual(control.accessibilityRole(), .radioGroup)
        let right = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 124))
        control.keyDown(with: right)
        XCTAssertEqual(inspector.settings.browserAppearance, .dark)
        inspector.setEditingEnabled(false); control.choose(0)
        XCTAssertEqual(inspector.settings.browserAppearance, .dark)
        inspector.setEditingEnabled(true)
        inspector.devicePicker.choose(0); XCTAssertNil(picker(inspector))
        inspector.devicePicker.choose(1); XCTAssertNil(picker(inspector))
        inspector.devicePicker.choose(2)
        XCTAssertEqual(picker(inspector)?.selectedIndex, 1)
    }

    @MainActor func testUndoPersistenceAndEmptyBrowserSurfaceStayIndependentOfAppAppearance() async throws {
        _ = NSApplication.shared
        defer { NSApp.appearance = nil }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "fralo-browser-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = SettingsStore(url: directory.appendingPathComponent("settings.json"))
        let controller = MainWindowController(store: store, preferences: defaults, restoreWindow: false)
        defer { controller.window?.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let root = try XCTUnwrap(controller.window?.contentView as? WorkbenchView)
        let inspector = try XCTUnwrap(root.right.body as? CompositionInspector)
        let stage = try XCTUnwrap(descendants(root).compactMap { $0 as? EmptyStageView }.first)
        controller.selectAppearance("light", persist: false)
        inspector.devicePicker.choose(2)
        try XCTUnwrap(picker(inspector)).choose(1)
        for _ in 0..<150 where stage.device?.display != .browser || stage.device?.browserAppearance != .dark { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(stage.device?.browserAppearance, .dark)
        XCTAssertEqual(stage.zone.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
        XCTAssertEqual(NSApp.appearance?.name, .aqua)
        XCTAssertEqual(try CompositionStore(legacy: store).load().browserAppearance, .dark)
        controller.selectAppearance("dark", persist: false)
        XCTAssertEqual(inspector.settings.browserAppearance, .dark)
        controller.undoChange(nil)
        XCTAssertEqual(inspector.settings.browserAppearance, .light)
        for _ in 0..<150 where stage.device?.browserAppearance != .light { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(stage.zone.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .aqua)
        controller.redoChange(nil)
        XCTAssertEqual(inspector.settings.browserAppearance, .dark)
        let reopened = MainWindowController(store: store, preferences: defaults, restoreWindow: false)
        defer { reopened.window?.close() }
        let reopenedRoot = try XCTUnwrap(reopened.window?.contentView as? WorkbenchView)
        XCTAssertEqual((reopenedRoot.right.body as? CompositionInspector)?.settings.browserAppearance, .dark)
    }
}
