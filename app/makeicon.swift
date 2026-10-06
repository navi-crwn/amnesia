// Menggambar ikon app Amnesia (1024x1024 PNG). Dipakai oleh build.sh.
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
// koordinat dari kiri-atas (sama dengan preview)
let flip = NSAffineTransform()
flip.translateX(by: 0, yBy: 1024)
flip.scaleX(by: 1, yBy: -1)
flip.concat()

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: y) }

// kotak membulat + bayangan
let box = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowBlurRadius = 40
shadow.shadowOffset = NSSize(width: 0, height: -20)
shadow.set()
rgb(0x6366F1).setFill()
box.fill()
NSGraphicsContext.restoreGraphicsState()

// gradien cyan -> indigo -> pink
NSGraphicsContext.saveGraphicsState()
box.addClip()
NSGradient(colors: [rgb(0x22D3EE), rgb(0x6366F1), rgb(0xEC4899)])!
    .draw(from: pt(0, 0), to: pt(1024, 1024), options: [])
NSGraphicsContext.restoreGraphicsState()

// perisai putih
let shield = NSBezierPath()
shield.move(to: pt(512, 236))
shield.curve(to: pt(752, 300), controlPoint1: pt(600, 290), controlPoint2: pt(680, 300))
shield.line(to: pt(752, 520))
shield.curve(to: pt(512, 820), controlPoint1: pt(752, 680), controlPoint2: pt(640, 770))
shield.curve(to: pt(272, 520), controlPoint1: pt(384, 770), controlPoint2: pt(272, 680))
shield.line(to: pt(272, 300))
shield.curve(to: pt(512, 236), controlPoint1: pt(344, 300), controlPoint2: pt(424, 290))
shield.close()
NSColor.white.setFill()
shield.fill()

// lubang kunci
rgb(0x6366F1).setFill()
NSBezierPath(ovalIn: NSRect(x: 450, y: 418, width: 124, height: 124)).fill()
let hole = NSBezierPath()
hole.move(to: pt(482, 500))
hole.line(to: pt(542, 500))
hole.line(to: pt(556, 650))
hole.line(to: pt(468, 650))
hole.close()
hole.fill()

// titik-titik yang memudar (ingatan yang hilang)
for (x, y, r, a) in [(812.0, 390.0, 20.0, 0.85), (858.0, 338.0, 14.0, 0.6), (893.0, 294.0, 9.0, 0.35)] {
    NSColor.white.withAlphaComponent(a).setFill()
    NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2)).fill()
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
