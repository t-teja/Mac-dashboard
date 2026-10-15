import AppKit
import Foundation

let size = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    let ink = NSColor(srgbRed: 0.063, green: 0.071, blue: 0.094, alpha: 1)
    let cream = NSColor(srgbRed: 0.957, green: 0.937, blue: 0.902, alpha: 1)
    let brass = NSColor(srgbRed: 0.878, green: 0.659, blue: 0.290, alpha: 1)
    ink.setFill()
    NSBezierPath(rect: rect).fill()

    let glow = NSGradient(colors: [
        NSColor(srgbRed: 0.16, green: 0.15, blue: 0.22, alpha: 1),
        ink
    ])
    glow?.draw(in: NSBezierPath(ovalIn: NSRect(x: 80, y: 80, width: 864, height: 864)), relativeCenterPosition: .zero)

    func star(_ center: CGPoint, radius: CGFloat) {
        cream.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
    }
    star(CGPoint(x: 180, y: 820), radius: 7)
    star(CGPoint(x: 790, y: 760), radius: 5)
    star(CGPoint(x: 250, y: 210), radius: 4)
    star(CGPoint(x: 840, y: 280), radius: 6)

    let planet = NSBezierPath(ovalIn: NSRect(x: 262, y: 262, width: 500, height: 500))
    let ring = NSBezierPath(ovalIn: NSRect(x: 120, y: 430, width: 784, height: 164))
    let tilt = NSAffineTransform()
    tilt.translateX(by: 512, yBy: 512)
    tilt.rotate(byDegrees: -18)
    tilt.translateX(by: -512, yBy: -512)
    ring.transform(using: tilt as AffineTransform)
    ring.lineWidth = 36
    brass.setStroke()
    ring.stroke()

    cream.setFill()
    planet.fill()

    // The near side of the ring passes in front of the planet.
    NSGraphicsContext.saveGraphicsState()
    let front = NSBezierPath(rect: NSRect(x: -400, y: -400, width: 1824, height: 912))
    front.transform(using: tilt as AffineTransform)
    front.addClip()
    ring.stroke()
    NSGraphicsContext.restoreGraphicsState()

    return true
}

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
    fputs("Could not render the icon\n", stderr)
    exit(1)
}

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = root.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let master = root.appendingPathComponent("icon-1024.png")
try png.write(to: master)

let sizes = [16, 32, 128, 256, 512]
for points in sizes {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let destination = iconset.appendingPathComponent(name)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        task.arguments = ["-z", "\(pixels)", "\(pixels)", master.path, "--out", destination.path]
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 { exit(task.terminationStatus) }
    }
}

let icns = root.appendingPathComponent("AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try iconutil.run()
iconutil.waitUntilExit()
if iconutil.terminationStatus != 0 { exit(iconutil.terminationStatus) }
try? FileManager.default.removeItem(at: iconset)
try? FileManager.default.removeItem(at: master)
print(icns.path)
