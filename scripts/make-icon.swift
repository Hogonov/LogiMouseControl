import AppKit
let folder = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 512, y: CGFloat(pixels) / 512)
        let bg = NSBezierPath(roundedRect: NSRect(x: 22, y: 22, width: 468, height: 468), xRadius: 110, yRadius: 110)
        NSColor(calibratedRed: 0.08, green: 0.13, blue: 0.11, alpha: 1).setFill(); bg.fill()
        let mouse = NSBezierPath(roundedRect: NSRect(x: 153, y: 100, width: 206, height: 312), xRadius: 101, yRadius: 101)
        NSGradient(starting: NSColor(calibratedRed: 0.58, green: 0.87, blue: 0.70, alpha: 1), ending: NSColor(calibratedRed: 0.76, green: 1, blue: 0.86, alpha: 1))!.draw(in: mouse, angle: 75)
        NSColor(calibratedRed: 0.08, green: 0.13, blue: 0.11, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 245, y: 295, width: 22, height: 57), xRadius: 11, yRadius: 11).fill()
        let line = NSBezierPath(); line.move(to: NSPoint(x: 256, y: 352)); line.line(to: NSPoint(x: 256, y: 412)); line.lineWidth = 3; NSColor(calibratedWhite: 0.12, alpha: 0.5).setStroke(); line.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(folder)/icon_\(size)x\(size)\(suffix).png"))
    }
}
