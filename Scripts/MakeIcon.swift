import Foundation
import AppKit
import CoreGraphics

// CmdBook icon: a terminal window with a ">_" prompt and a magnifying glass,
// drawn entirely with Core Graphics so no design tool or asset dependency is
// required. Coordinates below are top-left based for readability; the helpers
// convert them to Core Graphics' bottom-left coordinate system.

let canvas: CGFloat = 1024

func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: x, y: canvas - y - h, width: w, height: h)
}

func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: x, y: canvas - y)
}

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

func roundedPath(_ frame: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

guard let context = CGContext(
    data: nil, width: Int(canvas), height: Int(canvas),
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("Failed to create icon bitmap context\n", stderr)
    exit(1)
}

let navy = color(0.106, 0.169, 0.278)
let window = color(0.188, 0.290, 0.463)
let titleBar = color(0.141, 0.224, 0.373)
let frame = color(0.353, 0.471, 0.659)
let mint = color(0.498, 0.906, 0.769)
let ivory = color(0.918, 0.949, 1.0)

// Rounded-square app tile.
context.setFillColor(navy)
context.addPath(roundedPath(rect(56, 56, 912, 912), 208))
context.fillPath()

// Terminal window body and its title bar.
context.setFillColor(window)
context.addPath(roundedPath(rect(168, 236, 688, 500), 40))
context.fillPath()
context.setStrokeColor(frame)
context.setLineWidth(6)
context.addPath(roundedPath(rect(168, 236, 688, 500), 40))
context.strokePath()

context.setFillColor(titleBar)
context.addPath(roundedPath(rect(168, 236, 688, 104), 40))
context.fillPath()
context.fill(rect(168, 300, 688, 40))

let dots: [(CGFloat, CGColor)] = [
    (222, color(1.0, 0.42, 0.42)),
    (266, color(1.0, 0.784, 0.341)),
    (310, color(0.373, 0.827, 0.627))
]
for (x, tint) in dots {
    context.setFillColor(tint)
    context.fillEllipse(in: rect(x - 15, 271, 30, 30))
}

// ">_" prompt drawn as strokes so no font embedding is needed.
context.setStrokeColor(mint)
context.setLineWidth(38)
context.setLineCap(.round)
context.setLineJoin(.round)
context.beginPath()
context.move(to: point(248, 418))
context.addLine(to: point(340, 500))
context.addLine(to: point(248, 582))
context.strokePath()
context.beginPath()
context.move(to: point(380, 586))
context.addLine(to: point(536, 586))
context.strokePath()

// Magnifying glass: searching the command handbook.
let lens = rect(626, 592, 196, 196)
context.setFillColor(navy)
context.fillEllipse(in: lens)
context.setStrokeColor(ivory)
context.setLineWidth(30)
context.addEllipse(in: lens.insetBy(dx: 6, dy: 6))
context.strokePath()
context.setLineCap(.round)
context.beginPath()
context.move(to: point(792, 762))
context.addLine(to: point(872, 842))
context.strokePath()

guard CommandLine.arguments.count > 1,
      let image = context.makeImage() else {
    fputs("Usage: make-icon <output.png>\n", stderr)
    exit(1)
}
let representation = NSBitmapImageRep(cgImage: image)
guard let data = representation.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG\n", stderr)
    exit(1)
}
do {
    try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
} catch {
    fputs("Failed to write icon: \(error)\n", stderr)
    exit(1)
}
print("Wrote \(CommandLine.arguments[1])")
