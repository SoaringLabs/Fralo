import CoreGraphics
import CoreText

/// Neutral macOS Chrome artwork. All coordinates use the shell's 1500-point width.
/// No screenshot analysis or user browsing information enters the browser controls.
enum ChromeShellArtwork {
    static func draw(in context: CGContext, width: CGFloat) {
        let ink = color(0x5f6368), toolbar = color(0xffffff)
        context.saveGState(); defer { context.restoreGState() }
        context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: 102), cornerWidth: 16, cornerHeight: 16, transform: nil))
        context.clip()
        context.setFillColor(color(0xdee1e6)); context.fill(CGRect(x: 0, y: 0, width: width, height: 44))
        context.setFillColor(toolbar); context.fill(CGRect(x: 0, y: 44, width: width, height: 42))

        for (index, tint) in [0xff5f57, 0xfebc2e, 0x28c840].enumerated() {
            ellipse(CGRect(x: 22 + CGFloat(index) * 24, y: 17, width: 14, height: 14), color: color(UInt32(tint)), in: context)
        }

        // An active Chrome tab joins the toolbar with concave lower shoulders.
        let tab = CGMutablePath()
        tab.move(to: CGPoint(x: 108, y: 44))
        tab.addCurve(to: CGPoint(x: 120, y: 32), control1: CGPoint(x: 117, y: 44), control2: CGPoint(x: 120, y: 41))
        tab.addLine(to: CGPoint(x: 120, y: 20))
        tab.addQuadCurve(to: CGPoint(x: 132, y: 8), control: CGPoint(x: 120, y: 8))
        tab.addLine(to: CGPoint(x: 376, y: 8))
        tab.addQuadCurve(to: CGPoint(x: 388, y: 20), control: CGPoint(x: 388, y: 8))
        tab.addLine(to: CGPoint(x: 388, y: 32))
        tab.addCurve(to: CGPoint(x: 400, y: 44), control1: CGPoint(x: 388, y: 41), control2: CGPoint(x: 391, y: 44))
        tab.closeSubpath(); context.addPath(tab); context.setFillColor(toolbar); context.fillPath()

        context.setStrokeColor(ink); context.setLineWidth(1.6); context.setLineCap(.round); context.setLineJoin(.round)
        // Generic page favicon and title avoid inventing a URL for the user's screenshot.
        context.strokeEllipse(in: CGRect(x: 136, y: 17, width: 16, height: 16))
        line([(144, 17), (144, 33)], in: context); line([(136, 25), (152, 25)], in: context)
        context.strokeEllipse(in: CGRect(x: 140, y: 17, width: 8, height: 16))
        text("Untitled", at: CGPoint(x: 162, y: 30), in: context)
        line([(362, 20), (370, 28)], in: context); line([(370, 20), (362, 28)], in: context)
        line([(415, 24), (427, 24)], in: context); line([(421, 18), (421, 30)], in: context)
        line([(width - 31, 22), (width - 27, 26), (width - 23, 22)], in: context)

        // Navigation uses full arrows; the forward action is disabled in this neutral window.
        arrow(at: 27, forward: false, in: context)
        context.setStrokeColor(color(0xb6b9bd)); arrow(at: 61, forward: true, in: context)
        context.setStrokeColor(ink)
        let reload = CGMutablePath()
        reload.addArc(center: CGPoint(x: 96, y: 65), radius: 7, startAngle: -.pi / 4, endAngle: .pi * 1.55, clockwise: false)
        context.addPath(reload); context.strokePath()
        line([(103, 58), (103, 63), (98, 63)], in: context)

        let address = CGRect(x: 122, y: 49, width: width - 258, height: 32)
        context.addPath(CGPath(roundedRect: address, cornerWidth: 16, cornerHeight: 16, transform: nil))
        context.setFillColor(color(0xf1f3f4)); context.fillPath()
        // Site controls and bookmark star inside the omnibox; address intentionally blank.
        line([(135, 61), (149, 61)], in: context); line([(135, 69), (149, 69)], in: context)
        ellipse(CGRect(x: 138, y: 59, width: 4, height: 4), color: ink, in: context)
        ellipse(CGRect(x: 144, y: 67, width: 4, height: 4), color: ink, in: context)
        let star = CGMutablePath(), center = CGPoint(x: address.maxX - 20, y: 65)
        for index in 0..<10 {
            let angle = -.pi / 2 + CGFloat(index) * .pi / 5, radius: CGFloat = index.isMultiple(of: 2) ? 8 : 3.8
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            if index == 0 { star.move(to: point) } else { star.addLine(to: point) }
        }
        star.closeSubpath(); context.addPath(star); context.strokePath()

        // Extensions puzzle piece, profile silhouette, and Chrome's vertical More menu.
        let x = width - 110
        let puzzle = CGMutablePath()
        puzzle.move(to: CGPoint(x: x - 7, y: 58)); puzzle.addLine(to: CGPoint(x: x - 2, y: 58))
        puzzle.addCurve(to: CGPoint(x: x + 4, y: 58), control1: CGPoint(x: x - 4, y: 50), control2: CGPoint(x: x + 6, y: 50))
        puzzle.addLine(to: CGPoint(x: x + 8, y: 58)); puzzle.addLine(to: CGPoint(x: x + 8, y: 63))
        puzzle.addCurve(to: CGPoint(x: x + 8, y: 69), control1: CGPoint(x: x + 16, y: 61), control2: CGPoint(x: x + 16, y: 71))
        puzzle.addLine(to: CGPoint(x: x + 8, y: 73)); puzzle.addLine(to: CGPoint(x: x - 7, y: 73))
        puzzle.closeSubpath(); context.addPath(puzzle); context.strokePath()
        ellipse(CGRect(x: width - 80, y: 53, width: 24, height: 24), color: color(0xe8eaed), in: context)
        ellipse(CGRect(x: width - 72, y: 57, width: 8, height: 8), color: ink, in: context)
        context.saveGState()
        context.addEllipse(in: CGRect(x: width - 78, y: 55, width: 20, height: 20)); context.clip()
        ellipse(CGRect(x: width - 76, y: 67, width: 16, height: 14), color: ink, in: context)
        context.restoreGState()
        for y: CGFloat in [59, 65, 71] { ellipse(CGRect(x: width - 26.5, y: y - 1.5, width: 3, height: 3), color: ink, in: context) }
        context.setStrokeColor(color(0xdadce0)); context.setLineWidth(1)
        line([(0, 85.5), (width, 85.5)], in: context)
    }

    private static func arrow(at x: CGFloat, forward: Bool, in context: CGContext) {
        let direction: CGFloat = forward ? -1 : 1
        line([(x + direction * 5, 59), (x - direction, 65), (x + direction * 5, 71)], in: context)
        line([(x - direction, 65), (x + direction * 11, 65)], in: context)
    }
    private static func line(_ points: [(CGFloat, CGFloat)], in context: CGContext) {
        guard let first = points.first else { return }
        context.move(to: CGPoint(x: first.0, y: first.1))
        for point in points.dropFirst() { context.addLine(to: CGPoint(x: point.0, y: point.1)) }
        context.strokePath()
    }
    private static func ellipse(_ rect: CGRect, color: CGColor, in context: CGContext) {
        context.setFillColor(color); context.fillEllipse(in: rect)
    }
    private static func color(_ hex: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    private static func text(_ value: String, at origin: CGPoint, in context: CGContext) {
        let font = CTFontCreateWithName("Helvetica" as CFString, 13, nil)
        let string = CFAttributedStringCreate(nil, value as CFString, [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color(0x3c4043)] as CFDictionary)!
        context.saveGState(); context.translateBy(x: origin.x, y: origin.y); context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity; context.textPosition = .zero
        CTLineDraw(CTLineCreateWithAttributedString(string), context); context.restoreGState()
    }
}
