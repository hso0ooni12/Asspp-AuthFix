import AppKit

// A clean V identity generated during CI. No image downloads or private data.
let size = CGFloat(1024)
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let canvas = NSRect(x: 0, y: 0, width: size, height: size)
let shape = NSBezierPath(roundedRect: canvas, xRadius: 218, yRadius: 218)
NSColor.black.setFill()
shape.fill()

let v = NSBezierPath()
v.move(to: NSPoint(x: 252, y: 688))
v.line(to: NSPoint(x: 510, y: 315))
v.line(to: NSPoint(x: 772, y: 688))
v.lineWidth = 110
v.lineCapStyle = .round
v.lineJoinStyle = .round
NSColor.white.setStroke()
v.stroke()

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not render Velo icon")
}
let target = URL(fileURLWithPath: CommandLine.arguments[1])
try png.write(to: target, options: .atomic)
print("Velo icon written: \(target.path)")
