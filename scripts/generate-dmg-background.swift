#!/usr/bin/env swift
// Convert the selected installer artwork to a 2x TIFF for Finder.
import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift scripts/generate-dmg-background.swift output.tiff\n", stderr)
    exit(2)
}
let size = NSSize(width: 660, height: 400)
let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Resources/DMG/background.png")
guard let image = NSImage(contentsOf: source) else {
    fputs("Cannot read Resources/DMG/background.png\n", stderr)
    exit(1)
}
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1320, pixelsHigh: 800,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
context.translateBy(x: 0, y: 800); context.scaleBy(x: 2, y: -2)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
NSGraphicsContext.current?.imageInterpolation = .high
image.draw(in: NSRect(origin: .zero, size: size), from: .zero,
           operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
NSGraphicsContext.restoreGraphicsState()
bitmap.size = size
try bitmap.representation(using: .tiff, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
