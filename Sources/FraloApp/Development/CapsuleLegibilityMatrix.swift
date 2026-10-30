#if FRALO_DEV
import AppKit
import FraloDesignSystem

/// Renders the real viewing capsule over every backdrop class it can float above, for each
/// appearance and accessibility setting, and reports where each capsule sits. The backdrops are
/// real `CanvasSurface` artwork (or the stage material), so luminance-driven foreground flipping
/// runs through the production path. `scripts/check-capsule-legibility.sh` captures and measures it.
@MainActor
final class CapsuleLegibilityMatrix {
    struct Backdrop { let name: String; let color: NSColor?; var drawsText = false }
    struct Column { let name: String; let appearance: NSAppearance.Name; var increaseContrast = false; var reduceTransparency = false }
    static let backdrops: [Backdrop] = [
        Backdrop(name: "stage", color: nil),
        Backdrop(name: "white", color: .white),
        Backdrop(name: "cream", color: NSColor(srgbRed: 0.969, green: 0.957, blue: 0.933, alpha: 1)),
        Backdrop(name: "lightGray", color: NSColor(srgbRed: 0.91, green: 0.91, blue: 0.918, alpha: 1)),
        Backdrop(name: "midGray", color: NSColor(srgbRed: 0.557, green: 0.557, blue: 0.576, alpha: 1)),
        Backdrop(name: "midGreen", color: NSColor(srgbRed: 0.341, green: 0.478, blue: 0.42, alpha: 1)),
        Backdrop(name: "darkGreen", color: NSColor(srgbRed: 0.122, green: 0.239, blue: 0.22, alpha: 1)),
        Backdrop(name: "darkGray", color: NSColor(srgbRed: 0.173, green: 0.173, blue: 0.18, alpha: 1)),
        Backdrop(name: "black", color: .black),
        Backdrop(name: "text", color: .white, drawsText: true)
    ]
    static let columns: [Column] = [
        Column(name: "light", appearance: .aqua), Column(name: "dark", appearance: .darkAqua),
        Column(name: "light+contrast", appearance: .aqua, increaseContrast: true),
        Column(name: "dark+contrast", appearance: .darkAqua, increaseContrast: true),
        Column(name: "light+opaque", appearance: .aqua, reduceTransparency: true),
        Column(name: "dark+opaque", appearance: .darkAqua, reduceTransparency: true)
    ]
    static let cell = NSSize(width: 300, height: 64), labelWidth: CGFloat = 96, headerHeight: CGFloat = 24

    let window: NSWindow
    private var cells: [(backdrop: String, column: String, toolbar: ViewToolbar)] = []

    init() {
        let size = NSSize(width: Self.labelWidth + Self.cell.width * CGFloat(Self.columns.count),
                          height: Self.headerHeight + Self.cell.height * CGFloat(Self.backdrops.count))
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "胶囊可读性矩阵"; window.isReleasedWhenClosed = false
        let root = FlippedDocument(frame: NSRect(origin: .zero, size: size)); window.contentView = root
        for (c, column) in Self.columns.enumerated() {
            let header = NSTextField(labelWithString: column.name); header.font = .systemFont(ofSize: 11, weight: .medium)
            header.frame = NSRect(x: Self.labelWidth + CGFloat(c) * Self.cell.width + 8, y: 4, width: Self.cell.width - 16, height: 16)
            root.addSubview(header)
        }
        for (r, backdrop) in Self.backdrops.enumerated() {
            let y = Self.headerHeight + CGFloat(r) * Self.cell.height
            let label = NSTextField(labelWithString: backdrop.name); label.font = .systemFont(ofSize: 11)
            label.frame = NSRect(x: 8, y: y + Self.cell.height / 2 - 8, width: Self.labelWidth - 12, height: 16); root.addSubview(label)
            for (c, column) in Self.columns.enumerated() {
                let frame = NSRect(x: Self.labelWidth + CGFloat(c) * Self.cell.width, y: y, width: Self.cell.width, height: Self.cell.height)
                addCell(backdrop: backdrop, column: column, frame: frame, in: root)
            }
        }
    }

    private func addCell(backdrop: Backdrop, column: Column, frame: NSRect, in root: NSView) {
        let host = NSView(frame: frame); host.clipsToBounds = true
        host.appearance = NSAppearance(named: column.appearance); root.addSubview(host)
        var preferences = DesignPreferences()
        preferences.increaseContrast = column.increaseContrast; preferences.reduceTransparency = column.reduceTransparency
        let canvas: CanvasSurface?
        if let color = backdrop.color {
            let surface = CanvasSurface(frame: host.bounds)
            let size = NSSize(width: frame.width + 64, height: frame.height + 64)
            surface.image = NSImage(size: size, flipped: true) { rect in
                color.setFill(); rect.fill()
                if backdrop.drawsText {
                    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15, weight: .medium),
                                                                     .foregroundColor: NSColor(srgbRed: 0.42, green: 0.5, blue: 0.47, alpha: 1)]
                    for line in stride(from: CGFloat(18), to: size.height, by: 20) {
                        ("Sample entry · just for the demo · Sample entry" as NSString).draw(at: NSPoint(x: 12, y: line), withAttributes: attributes)
                    }
                }
                return true
            }
            surface.zoom = 1; host.addSubview(surface); canvas = surface
        } else {
            let stage = MaterialSurface(.workspace); stage.frame = host.bounds; stage.preferences = preferences
            host.addSubview(stage); canvas = nil
        }
        let toolbar = ViewToolbar(); toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.surface.preferences = preferences; toolbar.showStatus("100%")
        host.addSubview(toolbar)
        NSLayoutConstraint.activate([toolbar.centerXAnchor.constraint(equalTo: host.centerXAnchor), toolbar.centerYAnchor.constraint(equalTo: host.centerYAnchor),
                                     toolbar.heightAnchor.constraint(equalToConstant: ViewToolbar.height)])
        host.layoutSubtreeIfNeeded()
        if let canvas { toolbar.backdropLuminance = canvas.artworkLuminance(under: canvas.convert(toolbar.bounds, from: toolbar)) }
        cells.append((backdrop.name, column.name, toolbar))
    }

    func show() {
        // Measure on the sharpest display so hairlines render as users on Retina see them.
        let screen = NSScreen.screens.max { $0.backingScaleFactor < $1.backingScaleFactor } ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        window.setFrameTopLeftPoint(NSPoint(x: visible.minX + 20, y: visible.maxY - 20))
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    /// Frames are in window-frame points with a top-left origin, matching `screencapture -o -l`.
    func writeReport(to url: URL) {
        window.contentView?.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        let height = window.frame.height
        func topLeft(_ view: NSView) -> [String: CGFloat] {
            let rect = view.convert(view.bounds, to: nil)
            return ["x": rect.minX, "y": height - rect.maxY, "width": rect.width, "height": rect.height]
        }
        let entries: [[String: Any]] = cells.map { cell in
            ["backdrop": cell.backdrop, "column": cell.column, "capsule": topLeft(cell.toolbar), "readout": topLeft(cell.toolbar.zoom),
             "flipped": cell.toolbar.usesLightAppearance.map { $0 ? "light" : "dark" } ?? "window",
             "luminance": cell.toolbar.backdropLuminance.map { Double($0) } ?? NSNull()]
        }
        let report: [String: Any] = ["window": window.windowNumber, "frameWidth": window.frame.width, "frameHeight": height, "cells": entries]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: url) }
    }
}
#endif
