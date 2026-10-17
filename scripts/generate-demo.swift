#!/usr/bin/env swift
// Original fictional demo screens. No network, personal data, or third-party artwork.
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "examples", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
func color(_ hex: Int) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}
let ink = color(0x203E39), muted = color(0x76847D), accent = color(0xE8A96D)
func box(_ rect: NSRect, _ fill: NSColor, radius: CGFloat = 0) {
    fill.setFill(); NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}
func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat = 16,
          weight: NSFont.Weight = .regular, fill: NSColor = ink) {
    (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: fill
    ])
}
for index in 0..<3 {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1320, pixelsHigh: 2868,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
    let cg = graphics.cgContext
    cg.translateBy(x: 0, y: 2868); cg.scaleBy(x: 3, y: -3)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    box(NSRect(x: 0, y: 0, width: 440, height: 956), color(0xF7F5EE))
    text("9:41", x: 36, y: 20, size: 16, weight: .semibold)
    text("•••  100%", x: 330, y: 20, size: 12, weight: .semibold)
    text("FIELD NOTES", x: 28, y: 91, size: 12, weight: .bold, fill: muted)
    let titles = ["A little outside.", "Your collection.", "Small adventures."]
    text(titles[index], x: 28, y: 121, size: 31, weight: .bold)
    text(["Make room for a slower day.", "Keep the places you return to.", "Good days, one page at a time."][index],
         x: 28, y: 165, size: 15, fill: muted)
    box(NSRect(x: 28, y: 211, width: 384, height: 282), ink, radius: 24)
    // A small geometric landscape, drawn entirely here.
    color(0xEDC28A).setFill(); NSBezierPath(ovalIn: NSRect(x: 305, y: 240, width: 58, height: 58)).fill()
    let back = NSBezierPath()
    back.move(to: NSPoint(x: 28, y: 395)); back.line(to: NSPoint(x: 130, y: 277))
    back.line(to: NSPoint(x: 260, y: 431)); back.line(to: NSPoint(x: 412, y: 318))
    back.line(to: NSPoint(x: 412, y: 470)); back.line(to: NSPoint(x: 28, y: 470)); back.close()
    color(0x55786B).setFill(); back.fill()
    box(NSRect(x: 28, y: 400, width: 384, height: 93), ink, radius: 20)
    text(["The quiet trail", "Places worth keeping", "Weekend wanderings"][index],
         x: 49, y: 419, size: 23, weight: .semibold, fill: color(0xF7F5EE))
    text("A FICTIONAL DEMO  /  NO PERSONAL DATA", x: 49, y: 458, size: 9, weight: .medium, fill: color(0xB8CCC0))
    text(["On your list", "Recent pages", "This month"][index], x: 28, y: 527, size: 20, weight: .bold)
    let names = [["Walk by the water", "Find a new bookshop", "Take the scenic route"],
                 ["Morning light", "A pocket of green", "Notes from the coast"],
                 ["A day without a plan", "Coffee, then a walk", "The long way home"]][index]
    for (row, name) in names.enumerated() {
        let y = CGFloat(573 + row * 88)
        box(NSRect(x: 28, y: y, width: 384, height: 74), .white, radius: 16)
        box(NSRect(x: 44, y: y + 16, width: 42, height: 42), accent.withAlphaComponent(CGFloat(row + 2) / 5), radius: 12)
        text(String(format: "%02d", row + 1), x: 54, y: y + 28, size: 12, weight: .bold)
        text(name, x: 102, y: y + 15, size: 16, weight: .semibold)
        text("Sample entry · just for the demo", x: 102, y: y + 41, size: 11, fill: muted)
    }
    text("Today", x: 49, y: 895, size: 14, weight: .semibold)
    text("Collection", x: 172, y: 895, size: 14, fill: muted)
    text("Journal", x: 327, y: 895, size: 14, fill: muted)
    box(NSRect(x: 155, y: 938, width: 130, height: 5), ink, radius: 3)
    NSGraphicsContext.restoreGraphicsState()
    let file = output.appendingPathComponent(["01-today.png", "02-collection.png", "03-journal.png"][index])
    try bitmap.representation(using: .png, properties: [:])!.write(to: file)
    print(file.lastPathComponent)
}
