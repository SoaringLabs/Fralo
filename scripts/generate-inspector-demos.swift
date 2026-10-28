// Fixed fictional inspector illustrations. No input files or personal content are read.
// After `swift build`, compile with -I <debug> -L <debug> -lFraloCore.
// Place Fralo_FraloCore.bundle next to the generator executable; see the asset README.
import AppKit
import FraloCore

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Sources/FraloApp/Resources/InspectorDemos", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
func demo(width: Int, height: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
    let cg = graphics.cgContext
    cg.translateBy(x: 0, y: CGFloat(height)); cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    let w = CGFloat(width), h = CGFloat(height), landscape = w > h
    let gradient = NSGradient(starting: NSColor(srgbRed: 0.26, green: 0.41, blue: 0.66, alpha: 1), ending: NSColor(srgbRed: 0.61, green: 0.68, blue: 0.84, alpha: 1))!
    gradient.draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: 30)
    let pad = min(w, h) * 0.09, titleSize = min(w, h) * 0.11
    ("Fralo" as NSString).draw(at: NSPoint(x: pad, y: h * 0.18), withAttributes: [.font: NSFont.systemFont(ofSize: titleSize, weight: .bold), .foregroundColor: NSColor.white])
    ("DEMO" as NSString).draw(at: NSPoint(x: pad, y: h * 0.18 + titleSize * 1.4), withAttributes: [.font: NSFont.systemFont(ofSize: titleSize * 0.32, weight: .semibold), .foregroundColor: NSColor.white.withAlphaComponent(0.8)])
    let panel = landscape ? NSRect(x: w * 0.58, y: pad, width: w * 0.42 - pad, height: h - pad * 2)
                          : NSRect(x: pad, y: h * 0.48, width: w - pad * 2, height: h * 0.44)
    NSColor.white.withAlphaComponent(0.94).setFill(); NSBezierPath(roundedRect: panel, xRadius: pad * 0.4, yRadius: pad * 0.4).fill()
    for index in 0..<3 {
        let row = NSRect(x: panel.minX + pad * 0.4, y: panel.minY + pad * 0.55 + CGFloat(index) * panel.height * 0.26,
                         width: panel.width - pad * 0.8, height: panel.height * 0.16)
        NSColor(srgbRed: 0.85, green: 0.89, blue: 0.94, alpha: 1).setFill()
        NSBezierPath(roundedRect: row, xRadius: pad * 0.18, yRadius: pad * 0.18).fill()
    }
    return bitmap.representation(using: .png, properties: [:])!
}
for display in DisplayKind.allCases {
    for index in 0..<2 {
        var settings = CompositionSettings(); settings.display = display
        settings.orientation = index == 0 ? .portrait : .landscape
        settings.browser = index == 0 ? .safari : .chrome
        let size: (Int, Int)
        switch display {
        case .phone: size = index == 0 ? (1320, 2868) : (2868, 1320)
        case .tablet: size = index == 0 ? (1024, 1366) : (1366, 1024)
        case .browser: size = (1496, index == 0 ? 872 : 850)
        }
        let input = ImageInput(data: try demo(width: size.0, height: size.1), name: "fixed-demo.png")
        let image = try CompositionRenderer.render(input, settings: settings, maxDimension: 420).image
        let suffix = display == .browser ? (index == 0 ? "safari" : "chrome") : (index == 0 ? "portrait" : "landscape")
        let name = "\(display.rawValue)-\(suffix).png"
        try FrameRenderer.pngData(image).write(to: output.appendingPathComponent(name))
        print(name)
    }
}
