import AppKit
import XCTest
import FraloCore
import FraloDesignSystem
@testable import FraloApp

final class InspectorArtworkTests: XCTestCase {
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

    @MainActor func testReturningToCachedSourceDiscardsAnInFlightOtherSource() async throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.5, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 40, height: 80))
        let bytes = try FrameRenderer.pngData(XCTUnwrap(context.makeImage()))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("literal-source.png"); try bytes.write(to: file)
        let input = ImageInput(url: file)
        let loader = InspectorArtwork()
        let initial = expectation(description: "literal phone thumbnail")
        loader.load(input, display: .phone) { result in
            XCTAssertNotNil(result.frames.first ?? nil)
            initial.fulfill()
        }
        await fulfillment(of: [initial], timeout: 5)
        let stale = expectation(description: "browser request must not replace returned phone"); stale.isInverted = true
        loader.load(input, display: .browser) { _ in stale.fulfill() }
        var reusedCache = false
        loader.load(input, display: .phone) { _ in reusedCache = true }
        XCTAssertTrue(reusedCache, "Returning to the cached choice should immediately restore its artwork")
        await fulfillment(of: [stale], timeout: 0.4)
        XCTAssertEqual(try Data(contentsOf: file), bytes, "Thumbnail generation must not rewrite the original file")
    }
}
