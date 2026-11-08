import AppKit

// A clean V identity generated during CI. No image downloads or private data.
let size = CGFloat(1024)
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let canvas = NSRect(x: 0, y: 0, width: size, height: size)
let shape = NSBezierPath(roundedRect: canvas, xRadius: 218, yRadius: 218)
let bg = NSGradient(
    starting: NSColor(srgbRed: 0.030, green: 0.069, blue: 0.148, alpha: 1),
    ending: NSColor(srgbRed: 0.085, green: 0.182, blue: 0.280, alpha: 1)
)!
bg.draw(in: shape, angle: -35)

let line = NSBezierPath()
line.move(to: NSPoint(x: 260, y: 780))
line.line(to: NSPoint(x: 550, y: 780))
line.lineWidth = 24
line.lineCapStyle = .round
NSColor(srgbRed: 0.245, green: 0.844, blue: 0.913, alpha: 0.82).setStroke()
line.stroke()

let v = NSBezierPath()
v.move(to: NSPoint(x: 257, y: 680))
v.line(to: NSPoint(x: 510, y: 305))
v.line(to: NSPoint(x: 767, y: 680))
v.lineWidth = 112
v.lineCapStyle = .round
v.lineJoinStyle = .round
NSColor(srgbRed: 0.93, green: 0.978, blue: 0.996, alpha: 1).setStroke()
v.stroke()

let dot = NSBezierPath(ovalIn: NSRect(x: 457, y: 207, width: 106, height: 106))
NSColor(srgbRed: 0.245, green: 0.844, blue: 0.913, alpha: 1).setFill()
dot.fill()

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not render Velo icon")
}
let target = URL(fileURLWithPath: CommandLine.arguments[1])
try png.write(to: target, options: .atomic)
print("Velo icon written: \(target.path)")
