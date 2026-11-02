import XCTest
@testable import FraloLocalization

final class LocalizationTests: XCTestCase {
    func testLanguageNegotiationAndEnglishFallback() {
        for (preferences, expected) in [
            (["en-US"], "en"), (["zh-CN"], "zh-Hans"), (["zh-SG"], "zh-Hans"),
            (["zh-TW"], "zh-Hant"), (["zh-HK"], "zh-Hant"), (["ja-JP"], "ja"),
            (["fr-FR", "ja"], "ja"), (["de-DE"], "en"), ([], "en")
        ] {
            XCTAssertEqual(L10n.resolveLanguage(preferences), expected, "\(preferences)")
        }
    }

    func testSearchTermsIncludeEnglish() {
        let original = L10n.language; defer { L10n.setLanguage(original) }
        L10n.setLanguage("ja")
        XCTAssertEqual(L10n.tr("添加图片", alsoIn: ["en"]), ["画像を追加", "Add Images"])
    }

    func testAllLanguagesLoadRealBundleResources() {
        let expected = ["en": "Add Images", "zh-Hans": "添加图片", "zh-Hant": "加入圖片", "ja": "画像を追加"]
        for (language, title) in expected {
            XCTAssertEqual(L10n.translate("添加图片", language: language), title)
        }
        XCTAssertEqual(L10n.translate("添加图片", language: "unsupported"), "Add Images")
    }

    func testInterpolationPreservesUserTextAndAllowsDifferentWordOrder() {
        let filename = "日本語-{1}-%@-截图.png"
        XCTAssertEqual(L10n.translate("无法读取配置 \(filename)：\("Permission denied")", language: "en"),
                       "Unable to read settings \(filename): Permission denied")
        XCTAssertEqual(L10n.translate("将按 \("iPhone 18 Pro") 套框", language: "ja"),
                       "iPhone 18 Pro のフレームを適用します")
        XCTAssertEqual(L10n.translate("成功 \(2) 张 · 跳过 \(1) 张 · 失败 \(0) 张\n未处理 \(3) 张 · 用时 \("1.50") 秒", language: "zh-Hant"),
                       "成功 2 張 · 略過 1 張 · 失敗 0 張\n未處理 3 張 · 用時 1.50 秒")
    }

    func testMissingResourcesInCopiedStandaloneHostDoNotRequireTheSourceTree() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let host = try XCTUnwrap(Bundle(url: directory))
        XCTAssertEqual(L10n.resourceBundle(in: host).bundleURL, host.bundleURL)
    }

    func testCopiedAppResourcesTakePrecedenceOverBuildDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let resources = directory.appendingPathComponent("Example.app/Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "app.fralo.localization-test", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: resources.deletingLastPathComponent().appendingPathComponent("Info.plist"))
        let destination = resources.appendingPathComponent("Fralo_FraloLocalization.bundle")
        try FileManager.default.copyItem(at: L10n.resourceBundle().bundleURL, to: destination)
        let host = try XCTUnwrap(Bundle(url: resources.deletingLastPathComponent().deletingLastPathComponent()))
        XCTAssertEqual(L10n.resourceBundle(in: host).bundleURL.standardizedFileURL, destination.standardizedFileURL)
        for language in L10n.supportedLanguages {
            XCTAssertNotNil(L10n.resourceBundle(in: host).url(forResource: language.lowercased(), withExtension: "lproj"))
        }
    }
}
