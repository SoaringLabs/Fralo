#!/usr/bin/env swift
// Social preview for one locale: one screenshot split by a slanted compare seam, the original on a
// design grid on the left and the framed export on the gradient on the right, beside the hero copy.
// Usage: generate-og.swift OUTPUT.png COPY.json MEDIA_DIR
// COPY.json: {"lang": "ja", "headline": ["…"], "subtitle": "…", "footer": "…"}
// MEDIA_DIR holds icon.png, phone-original.png and phone-clear.png (the same screen, framed).
import AppKit

struct Copy: Decodable { let lang: String; let headline: [String]; let subtitle: String; let footer: String }

let args = CommandLine.arguments
let outPath = args[1]
let copy = try! JSONDecoder().decode(Copy.self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
let media = URL(fileURLWithPath: args[3])
func image(_ name: String) -> NSImage { NSImage(contentsOf: media.appendingPathComponent(name))! }

// 1200 × 630 pt (the 1.91:1 ratio every major preview card uses), rendered at 2×.
let pw: CGFloat = 1200, ph: CGFloat = 630, scale: CGFloat = 2
let bmp = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pw * scale), pixelsHigh: Int(ph * scale), bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let cg = NSGraphicsContext(bitmapImageRep: bmp)!.cgContext
cg.translateBy(x: 0, y: ph * scale); cg.scaleBy(x: scale, y: -scale)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)

func hex(_ h: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: a)
}
let ink = hex(0x1D1D1F)
let full = NSRect(x: 0, y: 0, width: pw, height: ph)
func fill(_ path: NSBezierPath, _ color: NSColor) { color.setFill(); path.fill() }
func fill(_ rect: NSRect, _ color: NSColor, radius: CGFloat = 0) { fill(NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius), color) }
func withShadow(_ alpha: CGFloat, blur: CGFloat, y: CGFloat, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow(); s.shadowColor = NSColor(white: 0, alpha: alpha); s.shadowBlurRadius = blur; s.shadowOffset = NSSize(width: 0, height: y); s.set()
    body()
    NSGraphicsContext.restoreGraphicsState()
}
func draw(_ img: NSImage, _ rect: NSRect) { img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil) }

// MARK: Text

let language = NSAttributedString.Key(kCTLanguageAttributeName as String)
func attributes(_ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor, tracking: CGFloat = 0, lineHeight: CGFloat? = nil, mono: Bool = false) -> [NSAttributedString.Key: Any] {
    let style = NSMutableParagraphStyle()
    if let lineHeight { style.minimumLineHeight = size * lineHeight; style.maximumLineHeight = size * lineHeight }
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    return [.font: font, .foregroundColor: color, .kern: tracking, .paragraphStyle: style, language: copy.lang]
}
func width(_ s: String, _ a: [NSAttributedString.Key: Any]) -> CGFloat { NSAttributedString(string: s, attributes: a).size().width }
@discardableResult
func paragraph(_ lines: [String], x: CGFloat, y: CGFloat, _ a: [NSAttributedString.Key: Any]) -> CGFloat {
    let string = NSAttributedString(string: lines.joined(separator: "\n"), attributes: a)
    let rect = NSRect(x: x, y: y, width: 2000, height: 1000)
    string.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    return ceil(string.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
}

/// Word boundaries from the system tokenizer, so CJK lines break between words, never inside one.
func tokens(_ s: String) -> [String] {
    let cf = s as CFString
    let tokenizer = CFStringTokenizerCreate(nil, cf, CFRange(location: 0, length: CFStringGetLength(cf)),
                                            kCFStringTokenizerUnitWordBoundary, Locale(identifier: copy.lang) as CFLocale)
    var out: [String] = []
    while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
        let r = CFStringTokenizerGetCurrentTokenRange(tokenizer)
        out.append(CFStringCreateWithSubstring(nil, cf, r) as String)
    }
    return out.isEmpty ? [s] : out
}
func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }
/// Greedy wrap at word boundaries.
func wrap(_ s: String, _ a: [NSAttributedString.Key: Any], within limit: CGFloat) -> [String] {
    var lines: [String] = [], line = ""
    for t in tokens(s) {
        if !trim(line).isEmpty, width(trim(line + t), a) > limit { lines.append(trim(line)); line = t } else { line += t }
    }
    if !trim(line).isEmpty { lines.append(trim(line)) }
    return lines
}
/// Two lines split at the word boundary that keeps them closest in width.
func balanced(_ s: String, _ a: [NSAttributedString.Key: Any]) -> [String] {
    let t = tokens(s)
    guard t.count > 1 else { return [s] }
    let splits = (1..<t.count).map { i in [trim(t[..<i].joined()), trim(t[i...].joined())] }.filter { !$0[0].isEmpty && !$0[1].isEmpty }
    return splits.min { max(width($0[0], a), width($0[1], a)) < max(width($1[0], a), width($1[1], a)) } ?? [s]
}

// MARK: Composition

let raw = image("phone-original.png"), framed = image("phone-clear.png")
let phone = NSRect(x: 532, y: 84, width: 340, height: 340 * framed.size.height / framed.size.width)
// The screen's place inside the phone-clear export (matches components/landing/sections.tsx).
let screen = NSRect(x: phone.minX + phone.width * 146 / 1612, y: phone.minY + phone.height * 132 / 3132,
                    width: phone.width * 1320 / 1612, height: phone.height * 2868 / 3132)

// Seam: leans about 7° and pivots on the handle at the screen's centre line.
let pivot = CGPoint(x: screen.midX.rounded(), y: 334), lean: CGFloat = 0.12
func seamX(_ y: CGFloat) -> CGFloat { pivot.x + (pivot.y - y) * lean }
func band(_ w: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: NSPoint(x: seamX(0) - w / 2, y: 0)); p.line(to: NSPoint(x: seamX(0) + w / 2, y: 0))
    p.line(to: NSPoint(x: seamX(ph) + w / 2, y: ph)); p.line(to: NSPoint(x: seamX(ph) - w / 2, y: ph)); p.close()
    return p
}
func side(left: Bool) -> NSBezierPath {
    let edge = left ? CGFloat(0) : pw, p = NSBezierPath()
    p.move(to: NSPoint(x: edge, y: 0)); p.line(to: NSPoint(x: seamX(0), y: 0)); p.line(to: NSPoint(x: seamX(ph), y: ph)); p.line(to: NSPoint(x: edge, y: ph)); p.close()
    return p
}

// Before: the bare screenshot on a design grid.
NSGraphicsContext.saveGraphicsState(); side(left: true).addClip()
fill(full, hex(0xEDEDF0))
hex(0x000000, 0.04).setStroke()
for x in stride(from: CGFloat(0), through: pw, by: 24) { NSBezierPath.strokeLine(from: NSPoint(x: x + 0.5, y: 0), to: NSPoint(x: x + 0.5, y: ph)) }
for y in stride(from: CGFloat(0), through: ph, by: 24) { NSBezierPath.strokeLine(from: NSPoint(x: 0, y: y + 0.5), to: NSPoint(x: pw, y: y + 0.5)) }
withShadow(0.08, blur: 3, y: 1) { draw(raw, screen) }
hex(0x000000, 0.14).setStroke(); NSBezierPath(rect: screen.insetBy(dx: 0.25, dy: 0.25)).stroke()
NSGraphicsContext.restoreGraphicsState()

// After: the framed export on the landing page's peach → blue gradient.
NSGraphicsContext.saveGraphicsState(); side(left: false).addClip()
NSGradient(starting: NSColor(srgbRed: 1, green: 0.8, blue: 0.68, alpha: 1), ending: NSColor(srgbRed: 0.62, green: 0.75, blue: 0.95, alpha: 1))!.draw(in: full, angle: -28)
let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [hex(0xFFFFFF, 0.3).cgColor, hex(0xFFFFFF, 0).cgColor] as CFArray, locations: [0, 1])!
cg.drawRadialGradient(glow, startCenter: CGPoint(x: 940, y: 140), startRadius: 0, endCenter: CGPoint(x: 940, y: 140), endRadius: 420, options: [])
withShadow(0.26, blur: 40, y: 26) { draw(framed, phone) }
NSGraphicsContext.restoreGraphicsState()

// Seam: a thin white rule with a hairline edge, like a split view divider.
withShadow(0.22, blur: 6, y: 0) { fill(band(4.5), hex(0x000000, 0.14)) }
fill(band(3), .white)

// Handle: a white disc with the system symbol for dragging sideways.
let handle = NSRect(x: pivot.x - 27, y: pivot.y - 27, width: 54, height: 54)
withShadow(0.22, blur: 16, y: 5) { fill(handle, .white, radius: 27) }
hex(0x000000, 0.08).setStroke(); NSBezierPath(ovalIn: handle.insetBy(dx: 0.5, dy: 0.5)).stroke()
let symbol = NSImage(systemSymbolName: "chevron.left.chevron.right", accessibilityDescription: nil)!
    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 19, weight: .bold).applying(.init(paletteColors: [ink])))!
draw(symbol, NSRect(x: handle.midX - symbol.size.width / 2, y: handle.midY - symbol.size.height / 2, width: symbol.size.width, height: symbol.size.height))

// File names on each side of the seam (user file names stay untranslated).
func pill(_ name: String, centerX: CGFloat, dark: Bool) {
    let a = attributes(14, .medium, dark ? .white : ink, mono: true)
    let w = width(name, a) + 24
    fill(NSRect(x: centerX - w / 2, y: 34, width: w, height: 28), dark ? hex(0x1D1D1F, 0.82) : hex(0xFFFFFF, 0.85), radius: 14)
    paragraph([name], x: centerX - w / 2 + 12, y: 39, a)
}
pill("01-today.png", centerX: seamX(48) - 100, dark: false)
pill("01-today-fralo.png", centerX: seamX(48) + 124, dark: true)

// MARK: Copy column

let left: CGFloat = 64, column: CGFloat = 450
withShadow(0.18, blur: 10, y: 3) { draw(image("icon.png"), NSRect(x: left - 5, y: 56, width: 52, height: 52)) }
paragraph(["Fralo"], x: left + 55, y: 67, attributes(26, .semibold, ink, tracking: -0.3))

// Headline: each dictionary line stays whole when it fits; a long one splits once at the most even
// word boundary. The size then shrinks until every line fits the column.
var size: CGFloat = 70
func headlineAttributes(_ s: CGFloat) -> [NSAttributedString.Key: Any] {
    attributes(s, .bold, ink, tracking: copy.lang == "en" ? -s * 0.023 : 0, lineHeight: 1.06)
}
let headline = copy.headline.flatMap { width($0, headlineAttributes(size)) > column ? balanced($0, headlineAttributes(size)) : [$0] }
while size > 48, headline.contains(where: { width($0, headlineAttributes(size)) > column }) { size -= 2 }
var y: CGFloat = 190 + (70 - size) * 0.5
y += paragraph(headline, x: left, y: y, headlineAttributes(size))

let subtitle = attributes(22, .medium, ink.withAlphaComponent(0.66), lineHeight: 1.32)
paragraph(wrap(copy.subtitle, subtitle, within: 400), x: left, y: max(y + 26, 352), subtitle)
paragraph([copy.footer], x: left, y: 540, attributes(17, .semibold, ink.withAlphaComponent(0.8)))

NSGraphicsContext.restoreGraphicsState()
try! bmp.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
