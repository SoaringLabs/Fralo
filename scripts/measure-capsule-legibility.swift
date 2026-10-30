// Measures a capture of the Debug capsule legibility matrix.
// Usage: swift scripts/measure-capsule-legibility.swift <report.json> <capture.png>
// Prints one row per backdrop × setting and exits non-zero when any cell fails.
import AppKit

struct Rect { let x, y, width, height: Double }
func rect(_ value: Any?) -> Rect {
    let d = value as! [String: Double]
    return Rect(x: d["x"]!, y: d["y"]!, width: d["width"]!, height: d["height"]!)
}

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let reportData = FileManager.default.contents(atPath: arguments[1]),
      let report = try? JSONSerialization.jsonObject(with: reportData) as? [String: Any],
      let image = NSImage(contentsOfFile: arguments[2]),
      let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!) else {
    FileHandle.standardError.write("usage: measure-capsule-legibility.swift <report.json> <capture.png>\n".data(using: .utf8)!); exit(2)
}
let scale = Double(bitmap.pixelsWide) / (report["frameWidth"] as! Double)

/// Gamma-encoded luma, the same scale the canvas uses to choose the capsule foreground.
func luma(_ x: Int, _ y: Int) -> Double {
    guard x >= 0, y >= 0, x < bitmap.pixelsWide, y < bitmap.pixelsHigh, let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return .nan }
    return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
}
func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
func meanRow(_ y: Double, from x0: Double, to x1: Double) -> Double {
    let py = Int((y * scale).rounded(.down)); var total = 0.0, count = 0.0
    for px in stride(from: Int(x0 * scale), to: Int(x1 * scale), by: 2) { let v = luma(px, py); if !v.isNaN { total += v; count += 1 } }
    return count > 0 ? total / count : .nan
}
func meanBand(_ y0: Double, _ y1: Double, from x0: Double, to x1: Double) -> Double {
    let rows = stride(from: y0, to: y1, by: 1 / scale).map { meanRow($0, from: x0, to: x1) }.filter { !$0.isNaN }
    return rows.reduce(0, +) / Double(max(1, rows.count))
}

/// How far the capsule's boundary stands out from the backdrop beside it, along one edge.
/// The background band sits 10–13 pt outside, beyond the capsule's shadow; the edge rows span the outermost 2 pt inside,
/// where the outline, rim highlight and glass body meet the backdrop.
func edgeVisibility(_ c: Rect, top: Bool) -> Double {
    let x0 = c.x + c.height, x1 = c.x + c.width - c.height   // straight run, clear of the rounded ends
    let background = top ? meanBand(c.y - 13, c.y - 10, from: x0, to: x1) : meanBand(c.y + c.height + 10, c.y + c.height + 13, from: x0, to: x1)
    var best = 0.0
    for step in stride(from: 0.0, to: 2.0, by: 1 / scale) {
        let row = top ? meanRow(c.y + step, from: x0, to: x1) : meanRow(c.y + c.height - step - 1 / scale, from: x0, to: x1)
        if !row.isNaN { best = max(best, abs(row - background)) }
    }
    let body = top ? meanBand(c.y + 4, c.y + 7, from: x0, to: x1) : meanBand(c.y + c.height - 7, c.y + c.height - 4, from: x0, to: x1)
    return max(best, abs(body - background))
}

/// WCAG contrast between the readout's text and the glass behind it.
func textContrast(_ r: Rect) -> Double {
    var values: [Double] = []
    for py in Int(r.y * scale)..<Int((r.y + r.height) * scale) {
        for px in Int(r.x * scale)..<Int((r.x + r.width) * scale) { let v = luma(px, py); if !v.isNaN { values.append(v) } }
    }
    guard !values.isEmpty else { return 0 }
    values.sort()
    let median = values[values.count / 2]
    // Glyph pixels are whichever tail lies farther from the glass body.
    let low = values[max(0, values.count / 100)], high = values[min(values.count - 1, values.count * 99 / 100)]
    let glyph = abs(high - median) > abs(median - low) ? high : low
    let a = linear(max(median, glyph)), b = linear(min(median, glyph))
    return (a + 0.05) / (b + 0.05)
}

let minimumEdge = 0.08, minimumText = 4.5
var failures = 0
print("capture scale \(scale)x\(scale < 2 ? " (hairlines cannot render faithfully below 2x)" : "")")
print(String(format: "%-11@ %-15@ %-7@ %7@ %7@ %7@  %@", "backdrop" as NSString, "setting" as NSString, "fg" as NSString,
             "top" as NSString, "bottom" as NSString, "text" as NSString, "result" as NSString))
for cell in report["cells"] as! [[String: Any]] {
    let capsule = rect(cell["capsule"]), readout = rect(cell["readout"])
    let top = edgeVisibility(capsule, top: true), bottom = edgeVisibility(capsule, top: false)
    let text = textContrast(readout)
    let passed = min(top, bottom) >= minimumEdge && text >= minimumText
    if !passed { failures += 1 }
    print(String(format: "%-11@ %-15@ %-7@ %7.3f %7.3f %6.1f:1  %@", cell["backdrop"] as! NSString, cell["column"] as! NSString,
                 cell["flipped"] as! NSString, top, bottom, text, (passed ? "ok" : "FAIL") as NSString))
}
print("edge ≥ \(minimumEdge) on both edges, text ≥ \(minimumText):1 — \(failures == 0 ? "all cells pass" : "\(failures) cell(s) fail")")
exit(failures == 0 ? 0 : 1)
