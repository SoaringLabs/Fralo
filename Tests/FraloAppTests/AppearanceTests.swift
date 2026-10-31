import AppKit
import XCTest
import FraloCore
import FraloDesignSystem
@testable import FraloApp

final class AppearanceTests: XCTestCase {
    @MainActor func testSettingsSynchronizePersistAndReopenWithoutChangingArtwork() async throws {
        _ = NSApplication.shared
        defer { NSApp.appearance = nil }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "fralo-appearance-\(UUID())"; let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("dark", forKey: "workbenchAppearance")
        let store = SettingsStore(url: directory.appendingPathComponent("settings.json"))
        let composition = CompositionStore(legacy: store); try composition.save(CompositionSettings())
        let savedComposition = try Data(contentsOf: composition.url)
        let context = try XCTUnwrap(CGContext(data: nil, width: 80, height: 160, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.6, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 80, height: 160))
        let sourceBytes = try FrameRenderer.pngData(XCTUnwrap(context.makeImage()))
        let source = directory.appendingPathComponent("sample.png"); try sourceBytes.write(to: source)
        let controller = MainWindowController(store: store, preferences: defaults, restoreWindow: false)
        defer { controller.settingsController?.window?.close(); controller.window?.close() }
        controller.importURLs([source])
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        let canvas = try XCTUnwrap(descendants(try XCTUnwrap(controller.window?.contentView)).compactMap { $0 as? CanvasSurface }.first)
        for _ in 0..<150 where canvas.image == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        let artwork = try XCTUnwrap(canvas.image)
        controller.showSettings(nil)
        let settings = try XCTUnwrap(controller.settingsController)
        XCTAssertEqual(settings.selection, .dark)
        XCTAssertTrue(settings.window?.isVisible == true)
        for (index, value, name): (Int, AppAppearance, NSAppearance.Name?) in [(1, .light, .aqua), (2, .dark, .darkAqua), (0, .system, nil)] {
            settings.choices.choose(index)
            XCTAssertEqual(controller.appearanceChoice, value)
            XCTAssertEqual(settings.selection, value)
            XCTAssertEqual(NSApp.appearance?.name, name)
            if let name {
                // Stands in for About, alert and update windows that Fralo does not own.
                let standalone = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 80, height: 60), styleMask: [.titled], backing: .buffered, defer: false)
                standalone.isReleasedWhenClosed = false
                defer { standalone.close() }
                for window in [controller.window, settings.window, standalone] {
                    XCTAssertEqual(window?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), name)
                }
            }
            XCTAssertEqual(defaults.string(forKey: "workbenchAppearance"), value.rawValue)
            let menu = controller.appearanceMenu()
            XCTAssertEqual(menu.items.filter { $0.state == .on }.count, 1)
            XCTAssertEqual(menu.items.first { $0.state == .on }?.representedObject as? String, value.rawValue)
        }
        controller.selectAppearance("light")
        XCTAssertEqual(settings.choices.selectedIndex, 1, "Quick appearance selection must update an open settings window")
        settings.window?.close(); controller.showSettings(nil)
        XCTAssertTrue(controller.settingsController === settings)
        XCTAssertTrue(settings.window?.isVisible == true)
        XCTAssertTrue(canvas.image === artwork, "Changing chrome must not request a new composition")
        XCTAssertEqual(try Data(contentsOf: composition.url), savedComposition)
        XCTAssertEqual(try Data(contentsOf: source), sourceBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
        let restarted = MainWindowController(store: store, preferences: defaults, restoreWindow: false)
        defer { restarted.window?.close() }
        XCTAssertEqual(restarted.appearanceChoice, .light)
        XCTAssertEqual(NSApp.appearance?.name, .aqua)
    }

    @MainActor func testPreviewOverrideDoesNotPersistAndInvalidAppearanceIsIgnored() async throws {
        _ = NSApplication.shared
        defer { NSApp.appearance = nil }
        let suite = "fralo-appearance-override-\(UUID())"; let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("dark", forKey: "workbenchAppearance")
        let store = SettingsStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"))
        let controller = MainWindowController(store: store, preferences: defaults, restoreWindow: false)
        defer { controller.settingsController?.window?.close(); controller.window?.close() }
        controller.selectAppearance("light", persist: false)
        controller.showSettings(nil)
        XCTAssertEqual(controller.settingsController?.selection, .light)
        XCTAssertEqual(defaults.string(forKey: "workbenchAppearance"), "dark")
        controller.selectAppearance("invalid")
        XCTAssertEqual(controller.appearanceChoice, .light)
        XCTAssertEqual(defaults.string(forKey: "workbenchAppearance"), "dark")
    }
}
