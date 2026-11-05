// Renders the Move "M" logo: Resources/AppIcon.iconset (for the .icns) and assets/logo.png (README).
// Usage: swift scripts/make-icon.swift
import AppKit

let out = URL(fileURLWithPath: "Resources/AppIcon.iconset")
try? FileManager.default.removeItem(at: out)
try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
try! FileManager.default.createDirectory(at: URL(fileURLWithPath: "assets"), withIntermediateDirectories: true)

/// A squircle tile with an "M" built from four window panes: two full-height columns and two
/// half-height diagonals meeting in the middle, the way Move snaps windows into a grid.
func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.1
    let tile = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(colors: [NSColor(red: 0.16, green: 0.18, blue: 0.26, alpha: 1),
                        NSColor(red: 0.05, green: 0.06, blue: 0.09, alpha: 1)])!.draw(in: path, angle: -90)

    // The M, inside a square of side `m`, centered.
    let m = tile.width * 0.56
    let ox = tile.midX - m / 2, oy = tile.midY - m / 2
    let stroke = m * 0.22                 // column width
    let r = stroke * 0.28                 // pane corner radius
    let accent = NSColor(red: 0.42, green: 0.66, blue: 1.0, alpha: 1)

    // Two columns.
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: ox, y: oy, width: stroke, height: m), xRadius: r, yRadius: r).fill()
    NSBezierPath(roundedRect: NSRect(x: ox + m - stroke, y: oy, width: stroke, height: m), xRadius: r, yRadius: r).fill()

    // The V: two slanted panes from the top corners to the middle.
    let v = NSBezierPath()
    let top = oy + m, mid = oy + m * 0.38, cx = ox + m / 2
    let half = stroke * 0.62
    v.move(to: NSPoint(x: ox + stroke * 0.15, y: top))
    v.line(to: NSPoint(x: ox + stroke * 0.15 + stroke * 1.1, y: top))
    v.line(to: NSPoint(x: cx + half * 0.5, y: mid + stroke * 0.55))
    v.line(to: NSPoint(x: cx + half * 0.5, y: mid))
    v.line(to: NSPoint(x: cx - half * 0.5, y: mid))
    v.close()
    let w = NSBezierPath()
    w.move(to: NSPoint(x: ox + m - stroke * 0.15, y: top))
    w.line(to: NSPoint(x: ox + m - stroke * 0.15 - stroke * 1.1, y: top))
    w.line(to: NSPoint(x: cx - half * 0.5, y: mid + stroke * 0.55))
    w.line(to: NSPoint(x: cx - half * 0.5, y: mid))
    w.line(to: NSPoint(x: cx + half * 0.5, y: mid))
    w.close()
    accent.setFill()
    v.fill(); w.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! render(512).write(to: URL(fileURLWithPath: "assets/logo.png"))
