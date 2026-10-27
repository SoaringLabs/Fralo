#if DEBUG
import AppKit
import XCTest
import FraloCore
import FraloDesignSystem
@testable import FraloApp

final class DevelopmentTests: XCTestCase {
    @MainActor func testPanelRenderingComparisonsChangeOneFactorAndRestoreBaseline() async throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SettingsStore(url: folder.appendingPathComponent("settings.json"))
        try CompositionStore(legacy: store).save(CompositionSettings())
        let before = try CompositionStore(legacy: store).load()
        let suite = "panel-probe-\(UUID())"; let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let controller = MainWindowController(store: store, preferences: preferences, restoreWindow: false)
        let window = try XCTUnwrap(controller.window); defer { window.close() }
        let root = try XCTUnwrap(window.contentView as? WorkbenchView)
        // Seed a nonzero baseline so C proves it removes a shadow, rather than comparing zero with zero.
        root.right.layer?.shadowOpacity = 0.17
        let probe = PanelRenderingProbe(window: window, showsControls: false)
        defer { probe.stop() }
        let originalClipping = root.right.surface.layer?.masksToBounds
        let originalShadow = root.right.layer?.shadowOpacity
        let workspaceMaterial = root.workspace.material
        let workspaceAlpha = root.workspace.effect.alphaValue
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        if #available(macOS 27.0, *) {
            let glass = try XCTUnwrap(descendants(root.right).compactMap { $0 as? NSGlassEffectView }.first)
            let interactive = glass.effectIsInteractive
            probe.select(.staticGlass)
            XCTAssertFalse(glass.effectIsInteractive)
            XCTAssertEqual(root.right.surface.layer?.masksToBounds, originalClipping)
            XCTAssertEqual(root.right.layer?.shadowOpacity, originalShadow)
            probe.select(.nativeShadow)
            XCTAssertEqual(glass.effectIsInteractive, interactive)
            XCTAssertEqual(root.right.layer?.shadowOpacity, 0)
            XCTAssertEqual(root.right.surface.layer?.masksToBounds, originalClipping)
            probe.select(.clipped)
            XCTAssertEqual(glass.effectIsInteractive, interactive)
            XCTAssertEqual(root.right.layer?.shadowOpacity, originalShadow)
            XCTAssertEqual(root.right.surface.layer?.masksToBounds, true)
            probe.select(.baseline)
            XCTAssertEqual(glass.effectIsInteractive, interactive)
        }
        XCTAssertEqual(root.right.surface.layer?.masksToBounds, originalClipping)
        XCTAssertEqual(root.right.layer?.shadowOpacity, originalShadow)
        XCTAssertEqual(root.workspace.material, workspaceMaterial)
        XCTAssertEqual(root.workspace.effect.alphaValue, workspaceAlpha)
        XCTAssertEqual(try CompositionStore(legacy: store).load(), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
    }

    @MainActor func testMaterialExperimentRetainsValuesWithoutFadingArtworkAndHonorsFallback() async throws {
        _ = NSApplication.shared
        let controller = DesignLabController()
        defer { controller.window?.close() }
        controller.selectPage(2)
        XCTAssertFalse(try XCTUnwrap(controller.window).isOpaque)
        XCTAssertEqual(controller.window?.backgroundColor.alphaComponent, 0)
        let experiment = try XCTUnwrap(controller.materialView)
        let pixels = experiment.canvas.image?.tiffRepresentation
        experiment.setTranslucency(opacity: 65, tint: 35)
        XCTAssertEqual(experiment.workspace.effect.alphaValue, 0.65, accuracy: 0.001)
        XCTAssertEqual(experiment.canvas.alphaValue, 1)
        XCTAssertEqual(experiment.panel.alphaValue, 1)
        XCTAssertEqual(experiment.canvas.image?.tiffRepresentation, pixels)
        controller.rebuild()
        XCTAssertEqual(controller.state.selectedPage, 2)
        XCTAssertEqual(controller.materialView.opacity.value, 65)
        XCTAssertEqual(controller.materialView.tint.value, 35)
        controller.state.preferences.reduceTransparency = true; controller.rebuild()
        XCTAssertTrue(controller.materialView.workspace.isUsingOpaqueFallback)
        XCTAssertTrue(controller.materialView.tintOverlay.isHidden)
        XCTAssertFalse(controller.materialView.opacity.isEnabled)
        XCTAssertFalse(controller.materialView.tint.isEnabled)
        XCTAssertTrue(try XCTUnwrap(controller.window?.contentView).isOpaque)
        controller.state.preferences.reduceTransparency = false; controller.rebuild()
        // Actual system accessibility settings retain precedence over local simulation.
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            XCTAssertEqual(controller.materialView.workspace.effect.alphaValue, 0.65, accuracy: 0.001)
        }
        controller.materialView.setTranslucency(opacity: 100, tint: 0)
        XCTAssertEqual(controller.materialView.opacity.value, 100)
        XCTAssertEqual(controller.materialView.tint.value, 0)
    }

    @MainActor func testLargeBatchViewportFillsPanelAndResizes() async {
        _ = NSApplication.shared
        let state = DesignLabState(); state.scenario.count = 100
        let scene = ScenarioWorkbench(state: state)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = scene
        var viewportHeights: [CGFloat] = []
        for height: CGFloat in [600, 900] {
            window.setContentSize(NSSize(width: 1200, height: height)); scene.layoutSubtreeIfNeeded()
            viewportHeights.append(scene.list.contentView.bounds.height)
            XCTAssertGreaterThan(scene.list.frame.height, scene.leftPanel.bounds.height - 160,
                                 "The source viewport should fill the space between the fixed header and footer")
        }
        XCTAssertEqual(viewportHeights[1] - viewportHeights[0], 300, accuracy: 2,
                       "Growing the panel must grow the source viewport, not leave a fixed-height list")
        var parent = scene.list.superview; var scrollAncestors = 0
        while let view = parent { if view is NSScrollView { scrollAncestors += 1 }; parent = view.superview }
        XCTAssertEqual(scrollAncestors, 0, "The source list must own its single scrolling viewport")
        scene.list.select(99); XCTAssertEqual(scene.list.selectedIndex, 99)
        window.close()
    }

    @MainActor func testShortInspectorContentDoesNotForceOverflow() async throws {
        _ = NSApplication.shared
        let state = DesignLabState(); state.scenario.transparent = true
        let scene = ScenarioWorkbench(state: state)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 650), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = scene; scene.layoutSubtreeIfNeeded()
        defer { window.close() }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        let scroll = try XCTUnwrap(descendants(scene.rightPanel).compactMap { $0 as? NSScrollView }.first { $0.bounds.height > 0 })
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertLessThanOrEqual(document.frame.height, scroll.contentView.bounds.height + 1,
                                 "A short device form should not inherit an oversized fixed tab height")
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
