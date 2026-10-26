#if DEBUG
import AppKit
import XCTest
import FraloCore
@testable import FraloApp

final class DevelopmentTests: XCTestCase {
    @MainActor func testSoftButtonBusyPreservesWidthAndRequestedAvailability() async {
        _ = NSApplication.shared
        var presses = 0
        let button = SoftButton("导出全部", role: .primary, symbol: "square.and.arrow.up") { presses += 1 }
        let size = button.intrinsicContentSize
        button.performClick(nil); XCTAssertEqual(presses, 1)
        button.isBusy = true; button.performClick(nil)
        XCTAssertEqual(presses, 1); XCTAssertFalse(button.isEnabled)
        XCTAssertEqual(button.intrinsicContentSize, size)
        XCTAssertEqual(button.accessibilityLabel(), "导出全部，正在处理")
        button.isEnabled = false; button.isBusy = false
        XCTAssertFalse(button.isEnabled)
        button.isEnabled = true; button.performClick(nil)
        XCTAssertEqual(presses, 2)
        XCTAssertEqual(button.accessibilityRole(), .button)
        XCTAssertEqual(button.accessibilityLabel(), "导出全部")
    }

    @MainActor func testSoftButtonTabLeavesTheControlInBothDirections() async {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.autorecalculatesKeyViewLoop = false
        let button = SoftButton("添加图片", symbol: "plus")
        button.frame = NSRect(x: 0, y: 0, width: 120, height: 34)
        let field = NSTextField(frame: NSRect(x: 150, y: 0, width: 120, height: 24))
        window.contentView?.addSubview(button); window.contentView?.addSubview(field)
        button.nextKeyView = field; field.nextKeyView = button
        for modifiers: NSEvent.ModifierFlags in [[], .shift] {
            window.makeFirstResponder(button)
            button.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48)!)
            XCTAssertTrue(window.firstResponder === field.currentEditor())
        }
        window.close()
    }

    @MainActor func testExperimentsDoNotChangeConfiguredProductSettings() async throws {
        _ = NSApplication.shared
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let oldPath = ProcessInfo.processInfo.environment["FRALO_SETTINGS_PATH"]
        setenv("FRALO_SETTINGS_PATH", path.path, 1)
        defer {
            if let oldPath { setenv("FRALO_SETTINGS_PATH", oldPath, 1) } else { unsetenv("FRALO_SETTINGS_PATH") }
            try? FileManager.default.removeItem(at: path)
        }
        let store = SettingsStore()
        let settings = RenderSettings(model: .iPhone17Pro, orientation: .landscape, padding: 17)
        try store.save(settings)
        let stateBefore = try Data(contentsOf: path)
        let state = DesignLabState()
        let scene = ScenarioWorkbench(state: state)
        scene.devicePicker.choose(2); scene.modePicker.choose(0); scene.moveSelection(1)
        XCTAssertEqual(try Data(contentsOf: path), stateBefore)
        XCTAssertEqual(try store.load(), settings)
    }

    @MainActor func testSceneSelectionChangesRealFixtureAndCollapseDoesNotChangeOutput() async {
        _ = NSApplication.shared
        let state = DesignLabState()
        XCTAssertFalse(state.samples.missingFixtures)
        let scene = ScenarioWorkbench(state: state)
        scene.frame = NSRect(x: 0, y: 0, width: 1100, height: 650)
        let original = scene.sampleImage()?.tiffRepresentation
        scene.moveSelection(1)
        XCTAssertEqual(state.scenario.selected, 1)
        XCTAssertNotEqual(scene.sampleImage()?.tiffRepresentation, original)
        let selected = scene.sampleImage()?.tiffRepresentation
        scene.toggleSidebar(); scene.layoutSubtreeIfNeeded()
        XCTAssertEqual(scene.sampleImage()?.tiffRepresentation, selected)
    }

    @MainActor func testMotionReplayDoesNotChangeTheScenarioPage() async {
        let state = DesignLabState()
        let motion = MotionExperiment(state: state)
        motion.workbench.toggleSidebar(); motion.workbench.togglePreview()
        XCTAssertFalse(state.scenario.collapsed)
        XCTAssertFalse(state.scenario.preview)
        XCTAssertTrue(motion.workbench.state.scenario.collapsed)
        XCTAssertTrue(motion.workbench.state.scenario.preview)
    }

    @MainActor func testScenePixelsDoNotDependOnWindowAppearanceOrMaterialPreferences() async {
        let state = DesignLabState(); let scene = ScenarioWorkbench(state: state)
        let original = scene.sampleImage()?.tiffRepresentation
        scene.appearance = NSAppearance(named: .darkAqua)
        state.preferences.reduceTransparency = true; state.preferences.increaseContrast = true
        scene.workspace.preferences = state.preferences
        XCTAssertEqual(scene.sampleImage()?.tiffRepresentation, original)
        XCTAssertTrue(scene.workspace.isUsingOpaqueFallback)
    }
}
#endif
