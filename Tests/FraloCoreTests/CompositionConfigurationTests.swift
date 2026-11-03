import XCTest
@testable import FraloCore

final class CompositionConfigurationTests: XCTestCase {
    private let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("fralo-recipe-tests")
    private func decode(_ document: [String: Any]) throws -> CompositionSettings {
        try CompositionConfiguration.decode(JSONSerialization.data(withJSONObject: document), relativeTo: directory)
    }

    func testFullGUISnapshotRoundTripsAndEveryFieldHasSchema() throws {
        var settings = CompositionSettings()
        settings.display = .browser; settings.browser = .chrome; settings.browserAppearance = .dark
        settings.mode = .background; settings.canvas = .story; settings.deviceX = -0.2; settings.deviceY = 0.3
        settings.background = .local; settings.localBackgroundPath = directory.appendingPathComponent("backdrop.png").path
        settings.pngLossless = false; settings.pngQuality = 0.2
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try CompositionConfiguration.decode(data, relativeTo: directory), settings)
        let properties = try XCTUnwrap(CompositionConfiguration.schema()["properties"] as? [String: Any])
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(properties.keys), Set(document.keys), "New GUI fields must be discoverable by agents")
    }

    func testPartialRecipeUsesBuiltInDefaultsAndResolvesBackgroundRelativeToFile() throws {
        let settings = try decode(["schemaVersion": 1, "display": "browser", "localBackgroundPath": "assets/background.png"])
        XCTAssertEqual(settings.display, .browser)
        XCTAssertEqual(settings.deviceScale, CompositionSettings().deviceScale)
        XCTAssertEqual(settings.localBackgroundPath, directory.appendingPathComponent("assets/background.png").path)
        XCTAssertEqual(try decode(["schemaVersion": 1, "localBackgroundPath": NSNull()]).localBackgroundPath, nil)
    }

    func testStrictFieldsVersionsTypesAndColors() throws {
        for document: [String: Any] in [[:], ["schemaVersion": 2], ["schemaVersion": true],
            ["schemaVersion": 1, "displayy": "phone"], ["schemaVersion": 1, "display": "watch"],
            ["schemaVersion": 1, "pngLossless": "true"], ["schemaVersion": 1, "deviceX": NSNull()],
            ["schemaVersion": 1, "backgroundColor": ["red": 1, "green": 0, "blue": 0, "alpha": 1]],
            ["schemaVersion": 1, "backgroundColor": ["red": 1]],
            ["schemaVersion": 1, "phoneModel": "iphone-16-pro"]] {
            XCTAssertThrowsError(try decode(document), "\(document)")
        }
    }

    func testPublishedNumberRangesMatchGUIValidation() throws {
        let properties = try XCTUnwrap(CompositionConfiguration.schema()["properties"] as? [String: [String: Any]])
        for (name, schema) in properties {
            guard let minimum = schema["minimum"] as? Double, let maximum = schema["maximum"] as? Double else { continue }
            XCTAssertNoThrow(try decode(["schemaVersion": 1, name: minimum]), name)
            XCTAssertNoThrow(try decode(["schemaVersion": 1, name: maximum]), name)
            XCTAssertThrowsError(try decode(["schemaVersion": 1, name: minimum - 0.01]), name)
            XCTAssertThrowsError(try decode(["schemaVersion": 1, name: maximum + 0.01]), name)
        }
    }
}
