import AppKit
import XCTest
import FraloCore
import FraloDesignSystem
@testable import FraloApp

final class InspectorArtworkTests: XCTestCase {
    @MainActor func testPackagedResourcesResolveInsideAppBeforeBuildFallback() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let hostURL = directory.appendingPathComponent("Host.app")
        let resources = hostURL.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let info: [String: String] = ["CFBundleIdentifier": "app.fralo.resource-test", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: hostURL.appendingPathComponent("Contents/Info.plist"))
        let copied = resources.appendingPathComponent("Fralo_FraloApp.bundle")
        try FileManager.default.copyItem(at: InspectorArtwork.resourceBundle().bundleURL, to: copied)
        let host = try XCTUnwrap(Bundle(url: hostURL))
        let resolved = InspectorArtwork.resourceBundle(in: host)
        XCTAssertEqual(resolved.bundleURL.standardizedFileURL, copied.standardizedFileURL)
        XCTAssertNotNil(resolved.url(forResource: "phone-portrait", withExtension: "png", subdirectory: "Resources/InspectorDemos"))
    }

    @MainActor func testDirectionKeepsControlIdentityKeyboardFocusAndEditsRealSettings() async throws {
        _ = NSApplication.shared
        let inspector = CompositionInspector(settings: CompositionSettings())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }; window.contentView = inspector
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        let direction = try XCTUnwrap(descendants(inspector).compactMap { $0 as? VisualChoiceGroup }.first { $0.accessibilityLabel() == "方向" })
        window.makeFirstResponder(direction)
        direction.choose(1)
        XCTAssertEqual(inspector.settings.orientation, .landscape)
        let restored = try XCTUnwrap(window.firstResponder as? VisualChoiceGroup)
        XCTAssertTrue(restored === direction, "Changing direction must preserve the control and its focus")
        XCTAssertEqual(restored.accessibilityLabel(), "方向")
        restored.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 123)!)
        XCTAssertEqual(inspector.settings.orientation, .portrait)
        XCTAssertTrue((window.firstResponder as? NSView)?.isDescendant(of: inspector) == true)
    }

    @MainActor func testFixedDemoAssetsExistForEveryDeviceAndAreReused() async throws {
        let loader = InspectorArtwork()
        for display in DisplayKind.allCases {
            var first: InspectorArtworkResult?
            loader.load(display: display) { first = $0 }
            let result = try XCTUnwrap(first)
            XCTAssertEqual(result.frames.count, 2)
            let portrait = try XCTUnwrap(result.frames[0]), landscape = try XCTUnwrap(result.frames[1])
            if display != .browser {
                XCTAssertGreaterThan(portrait.height, portrait.width)
                XCTAssertGreaterThan(landscape.width, landscape.height)
            }
            XCTAssertTrue(result.backgrounds.allSatisfy { $0 != nil })
            loader.load(display: display) { cached in
                XCTAssertTrue(cached.frames[0] === portrait)
                XCTAssertTrue(cached.frames[1] === landscape)
            }
        }
    }
}
