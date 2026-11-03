import Foundation

/// The GUI's versioned composition document, with defaults for omitted fields.
/// CLI diagnostics translate these typed issues at the command boundary.
public enum CompositionConfigurationIssue: Error {
    case invalidDocument
    case unknownFields([String])
    case missingVersion
    case unsupportedVersion
}

public enum CompositionConfiguration {
    public static func defaults() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(CompositionSettings())) as! [String: Any]
    }

    public static func decode(_ data: Data, relativeTo directory: URL) throws -> CompositionSettings {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CompositionConfigurationIssue.invalidDocument
        }
        let properties = try schema()["properties"] as! [String: Any]
        let unknown = object.keys.filter { properties[$0] == nil }.sorted()
        guard unknown.isEmpty else { throw CompositionConfigurationIssue.unknownFields(unknown) }
        guard let version = object["schemaVersion"] else { throw CompositionConfigurationIssue.missingVersion }
        // JSONDecoder enforces integer type (including rejecting booleans).
        struct Version: Decodable { let schemaVersion: Int }
        let parsed = try JSONDecoder().decode(Version.self, from: JSONSerialization.data(withJSONObject: ["schemaVersion": version]))
        guard parsed.schemaVersion == 1 else { throw CompositionConfigurationIssue.unsupportedVersion }
        for name in ["backgroundColor", "backgroundEndColor", "jpegFill"] {
            if let color = object[name] as? [String: Any] {
                let unknown = color.keys.filter { !["red", "green", "blue"].contains($0) }.map { "\(name).\($0)" }.sorted()
                guard unknown.isEmpty else { throw CompositionConfigurationIssue.unknownFields(unknown) }
            }
        }
        var merged = try defaults()
        object.forEach { merged[$0.key] = $0.value }
        var result = try JSONDecoder().decode(CompositionSettings.self, from: JSONSerialization.data(withJSONObject: merged)).validated()
        if let path = result.localBackgroundPath {
            let expanded = (path as NSString).expandingTildeInPath
            let base = URL(fileURLWithPath: directory.path, isDirectory: true)
            result.localBackgroundPath = URL(fileURLWithPath: expanded, relativeTo: base).standardizedFileURL.path
        }
        return result
    }

    /// JSON Schema and runtime decoding share the exact GUI property names and enum IDs.
    public static func schema() throws -> [String: Any] {
        var properties: [String: Any] = [:]
        let defaults = try defaults()
        func enumeration(_ name: String, _ values: [String]) {
            properties[name] = ["type": "string", "enum": values, "default": defaults[name]!] as [String: Any]
        }
        enumeration("display", DisplayKind.allCases.map(\.rawValue))
        enumeration("phoneModel", CompositionSettings.phoneModels.map(\.rawValue))
        enumeration("orientation", Orientation.allCases.map(\.rawValue))
        enumeration("browser", BrowserStyle.allCases.map(\.rawValue))
        enumeration("browserAppearance", BrowserAppearance.allCases.map(\.rawValue))
        enumeration("windowRatio", WindowRatio.allCases.map(\.rawValue))
        enumeration("mode", CompositionMode.allCases.map(\.rawValue))
        enumeration("canvas", CanvasRatio.allCases.map(\.rawValue))
        enumeration("background", BackgroundKind.allCases.map(\.rawValue))
        enumeration("transparentShadow", ShadowStyle.allCases.map(\.rawValue))
        enumeration("backgroundShadow", ShadowStyle.allCases.map(\.rawValue))
        enumeration("format", ImageFormat.allCases.map(\.rawValue))
        let ranges: [String: ClosedRange<Double>] = [
            "deviceScale": 0.1...1.5, "deviceX": -1...1, "deviceY": -1...1, "deviceOpacity": 0...1,
            "backgroundScale": 1...4, "backgroundX": -1...1, "backgroundY": -1...1, "backgroundOpacity": 0...1,
            "jpegQuality": 0.1...1, "pngQuality": 0.1...1
        ]
        for (name, range) in ranges {
            properties[name] = ["type": "number", "minimum": range.lowerBound, "maximum": range.upperBound, "default": defaults[name]!] as [String: Any]
        }
        let component: [String: Any] = ["type": "number", "minimum": 0, "maximum": 1]
        for name in ["backgroundColor", "backgroundEndColor", "jpegFill"] {
            properties[name] = ["type": "object", "properties": ["red": component, "green": component, "blue": component],
                                "required": ["red", "green", "blue"], "additionalProperties": false, "default": defaults[name]!] as [String: Any]
        }
        properties["pngLossless"] = ["type": "boolean", "default": defaults["pngLossless"]!]
        properties["schemaVersion"] = ["type": "integer", "const": 1]
        properties["localBackgroundPath"] = ["type": ["string", "null"], "description": "Relative to the configuration file; use an absolute path when piping a config snapshot."]
        return ["$schema": "https://json-schema.org/draft/2020-12/schema", "title": "Fralo composition configuration v1",
                "type": "object", "required": ["schemaVersion"], "additionalProperties": false, "properties": properties]
    }
}
