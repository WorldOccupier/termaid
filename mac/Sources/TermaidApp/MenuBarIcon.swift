import AppKit

/// The app logo as a menu-bar template glyph: a box around a tiny flowchart (box → diamond → two ends).
/// Drawn in the logo's 100-unit grid and scaled to the 18pt menu-bar size.
enum MenuBarIcon {
    static let size = NSSize(width: 18, height: 18)

    static func make() -> NSImage {
        let image = NSImage(size: size, flipped: true) { rect in
            let scale = rect.width / 100
            NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)
            NSColor.black.set()
            drawFrame()
            drawFlowchart()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "termaid"
        return image
    }

    private static func drawFrame() {
        let frame = NSBezierPath(roundedRect: NSRect(x: 8, y: 8, width: 84, height: 84), xRadius: 22, yRadius: 22)
        frame.lineWidth = 9
        frame.stroke()
    }

    private static func drawFlowchart() {
        NSBezierPath(roundedRect: NSRect(x: 36, y: 24, width: 28, height: 15), xRadius: 3, yRadius: 3).fill()
        let diamond = NSBezierPath()
        diamond.move(to: NSPoint(x: 50, y: 40))
        [NSPoint(x: 61, y: 51), NSPoint(x: 50, y: 62), NSPoint(x: 39, y: 51)].forEach(diamond.line(to:))
        diamond.close()
        diamond.fill()
        let edges = NSBezierPath()
        edges.lineWidth = 5
        edges.move(to: NSPoint(x: 44, y: 57)); edges.line(to: NSPoint(x: 34, y: 65))
        edges.move(to: NSPoint(x: 56, y: 57)); edges.line(to: NSPoint(x: 66, y: 65))
        edges.stroke()
        for x in [22.0, 54.0] {
            NSBezierPath(roundedRect: NSRect(x: x, y: 64, width: 24, height: 13), xRadius: 6.5, yRadius: 6.5).fill()
        }
    }
}
