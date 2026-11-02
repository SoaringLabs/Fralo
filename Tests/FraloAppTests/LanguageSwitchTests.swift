import AppKit
import XCTest
import FraloCore
import FraloLocalization
@testable import FraloApp

final class LanguageSwitchTests: XCTestCase {
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }

    @MainActor func testApplyingALanguageRebuildsTheWorkbenchAndKeepsTheBatch() async throws {
        _ = NSApplication.shared
        let original = L10n.language
        let previousMenu = NSApp.mainMenu
        defer { L10n.setLanguage(original); NSApp.mainMenu = previousMenu }
        L10n.setLanguage("zh-Hans")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let context = try XCTUnwrap(CGContext(data: nil, width: 80, height: 160, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.6, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 80, height: 160))
        let bytes = try FrameRenderer.pngData(XCTUnwrap(context.makeImage()))
        let urls = try (0..<2).map { index -> URL in
            let url = directory.appendingPathComponent("shot-\(index).png"); try bytes.write(to: url); return url
        }
        let delegate = AppDelegate()
        let old = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")), restoreWindow: false)
        delegate.adoptForTesting(old)
        old.importURLs(urls)
        old.showSettings(nil)
        let settings = try XCTUnwrap(old.settingsController)
        defer { settings.window?.close(); delegate.mainController?.window?.close(); old.window?.close() }

        XCTAssertTrue(delegate.applyLanguage("en"))
        XCTAssertEqual(L10n.language, "en")
        let replacement = try XCTUnwrap(delegate.mainController)
        XCTAssertFalse(replacement === old)
        XCTAssertTrue(replacement.settingsController === settings, "Settings stays open in place")
        XCTAssertNil(old.settingsController)
        XCTAssertEqual(settings.window?.title, "Fralo Settings")
        XCTAssertEqual(settings.sidebar.accessibilityLabel(), "Settings Categories")
        let menuTitles = Set((NSApp.mainMenu?.items ?? []).compactMap { $0.submenu?.title })
        XCTAssertTrue(menuTitles.contains("File")); XCTAssertFalse(menuTitles.contains("文件"))
        let texts = descendants(try XCTUnwrap(replacement.window?.contentView)).compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertTrue(texts.contains("Images"), "The rebuilt workbench uses the new language")
        XCTAssertFalse(texts.contains("图片"))
        XCTAssertEqual(replacement.batchCountForTesting, 2, "The batch survives the switch")

        XCTAssertTrue(delegate.applyLanguage("en"), "The current language needs no rebuild")
        XCTAssertTrue(delegate.mainController === replacement)
    }

    @MainActor func testSetLanguagePostsOnlyOnChange() {
        let original = L10n.language
        defer { L10n.setLanguage(original) }
        L10n.setLanguage("en")
        var posts = 0
        let token = NotificationCenter.default.addObserver(forName: L10n.languageDidChange, object: nil, queue: nil) { _ in posts += 1 }
        defer { NotificationCenter.default.removeObserver(token) }
        XCTAssertTrue(L10n.setLanguage("ja-JP")); XCTAssertEqual(L10n.language, "ja"); XCTAssertEqual(L10n.tr("添加图片"), "画像を追加")
        XCTAssertFalse(L10n.setLanguage("ja"))
        XCTAssertEqual(posts, 1)
    }
}
