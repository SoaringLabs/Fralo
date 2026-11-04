#!/usr/bin/env swift
// Original fictional wide demo screens (web, tablet) matching scripts/generate-demo.swift.
// Usage: generate-wide-demo.swift OUTPUT.png WIDTH_PT HEIGHT_PT SCALE [web]
import AppKit

let args = CommandLine.arguments
let outPath = args[1]
let pw = CGFloat(Double(args[2])!), ph = CGFloat(Double(args[3])!)  // points
let scale = CGFloat(Double(args[4])!)
let web = args.count > 5 && args[5] == "web"

func color(_ hex: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: a)
}
let ink = color(0x203E39), muted = color(0x76847D), accent = color(0xE8A96D), paper = color(0xF7F5EE)
func box(_ r: NSRect, _ f: NSColor, radius: CGFloat = 0) { f.setFill(); NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill() }
func text(_ v: String, _ x: CGFloat, _ y: CGFloat, _ s: CGFloat, _ w: NSFont.Weight = .regular, _ f: NSColor = ink) {
    (v as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: s, weight: w), .foregroundColor: f])
}
let W = Int(pw * scale), H = Int(ph * scale)
let bmp = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let cg = NSGraphicsContext(bitmapImageRep: bmp)!.cgContext
cg.translateBy(x: 0, y: CGFloat(H)); cg.scaleBy(x: scale, y: -scale)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
box(NSRect(x: 0, y: 0, width: pw, height: ph), paper)
let m: CGFloat = web ? 64 : 40
var top: CGFloat = web ? 28 : 36
if web {
    text("Field Notes", m, top, 20, .bold)
    for (i, item) in ["Today", "Collection", "Journal"].enumerated() { text(item, pw - m - 330 + CGFloat(i) * 110, top + 3, 15, .medium, i == 0 ? ink : muted) }
    top += 70
} else {
    text("9:41", 24, 12, 14, .semibold); text("100%", pw - 64, 12, 12, .semibold)
}
text("FIELD NOTES", m, top, 12, .bold, muted)
text("A little outside.", m, top + 24, web ? 44 : 36, .bold)
text("Make room for a slower day.", m, top + (web ? 82 : 72), 17, .regular, muted)
let heroY = top + (web ? 126 : 112)
let heroW = (pw - m * 2) * 0.58, heroH = ph - heroY - m
box(NSRect(x: m, y: heroY, width: heroW, height: heroH), ink, radius: 26)
color(0xEDC28A).setFill(); NSBezierPath(ovalIn: NSRect(x: m + heroW - 120, y: heroY + 36, width: 70, height: 70)).fill()
let p = NSBezierPath()
p.move(to: NSPoint(x: m, y: heroY + heroH * 0.75)); p.line(to: NSPoint(x: m + heroW * 0.3, y: heroY + heroH * 0.35))
p.line(to: NSPoint(x: m + heroW * 0.62, y: heroY + heroH * 0.82)); p.line(to: NSPoint(x: m + heroW, y: heroY + heroH * 0.45))
p.line(to: NSPoint(x: m + heroW, y: heroY + heroH)); p.line(to: NSPoint(x: m, y: heroY + heroH)); p.close()
color(0x55786B).setFill(); p.fill()
box(NSRect(x: m, y: heroY + heroH - 96, width: heroW, height: 96), ink, radius: 22)
text("The quiet trail", m + 26, heroY + heroH - 76, 26, .semibold, paper)
text("A FICTIONAL DEMO  /  NO PERSONAL DATA", m + 26, heroY + heroH - 36, 10, .medium, color(0xB8CCC0))
let lx = m + heroW + 28, lw = pw - m - lx
text("On your list", lx, heroY, 22, .bold)
let names = ["Walk by the water", "Find a new bookshop", "Take the scenic route", "Coffee, then a walk"]
let rowH = min(84, (heroH - 50) / CGFloat(names.count) - 10)
for (i, n) in names.enumerated() {
    let y = heroY + 46 + CGFloat(i) * (rowH + 10)
    box(NSRect(x: lx, y: y, width: lw, height: rowH), .white, radius: 16)
    box(NSRect(x: lx + 16, y: y + (rowH - 42) / 2, width: 42, height: 42), accent.withAlphaComponent(CGFloat(i + 2) / 6), radius: 12)
    text(String(format: "%02d", i + 1), lx + 27, y + rowH / 2 - 8, 12, .bold)
    text(n, lx + 74, y + rowH / 2 - 20, 16, .semibold)
    text("Sample entry · just for the demo", lx + 74, y + rowH / 2 + 4, 11, .regular, muted)
}
NSGraphicsContext.restoreGraphicsState()
try! bmp.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) \(W)x\(H)")
