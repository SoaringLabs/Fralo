#if FRALO_DEV
import AppKit
import FraloCore
import FraloDesignSystem

/// Development fixtures only. Neither these images nor this loader are Release resources.
@MainActor
final class LabSamples {
    let sources: [NSImage]
    let backgrounds: [NSImage]
    let framedPhones: [NSImage?]
    var framedPhone: NSImage? { framedPhones.first ?? nil }
    func phone(at index: Int) -> NSImage? { framedPhones.isEmpty ? nil : framedPhones[index % framedPhones.count] }
    let missingFixtures: Bool
    private static let sourceNames = ["01-today.png", "02-collection.png", "03-journal.png"]
    init() {
        let checkoutRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let candidates = [Bundle.main.resourceURL?.appendingPathComponent("DesignLabFixtures"), checkoutRoot.appendingPathComponent("Fixtures")].compactMap { $0 }
        let root = candidates.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("01-today.png").path) }
        sources = Self.sourceNames.compactMap { name in root.flatMap { NSImage(contentsOf: $0.appendingPathComponent(name)) } }
        backgrounds = ["warm-gray.png", "mist-blue.png", "sage-gray.png"].compactMap { name in root.flatMap { NSImage(contentsOf: $0.appendingPathComponent(name)) } }
        missingFixtures = sources.count != 3 || backgrounds.count != 3
        framedPhones = Self.sourceNames.map { name in
            guard let root, let rendered = try? FrameRenderer.render(ImageInput(url: root.appendingPathComponent(name)), settings: .init(), maxDimension: 1000) else { return nil }
            return NSImage(cgImage: rendered.image, size: .init(width: rendered.image.width, height: rendered.image.height))
        }
    }
    func entries(count: Int = 3, longNames: Bool = false) -> [FraloDesignSystem.BatchEntry] {
        (0..<count).map { index in
            .init(id: "sample-\(index)", title: longNames ? "第\(index + 1)张-包含中英文与较长名称的截图-Screenshot-long-file-name.png" : "\(String(format: "%02d", index + 1))-sample.png",
                  detail: index == 2 ? "失败样例 · 可重试" : "开发样例", image: sources.isEmpty ? nil : sources[index % sources.count], failed: index == 2)
        }
    }
}
#endif
