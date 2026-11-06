import Foundation
import AppKit

// Renders the article's "before / after" causal chain to a 2x PNG.
// Kept dependency-free: only AppKit/CoreGraphics, same approach as MakeIcon.swift.

let width: CGFloat = 680
let height: CGFloat = 250
let scale: CGFloat = 2

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
}

let redFill = color(0.988, 0.922, 0.922)
let redFillStrong = color(0.969, 0.757, 0.757)
let redStroke = color(0.639, 0.176, 0.176)
let redText = color(0.314, 0.122, 0.122)
let redSub = color(0.475, 0.122, 0.122)

let tealFill = color(0.882, 0.961, 0.933)
let tealFillStrong = color(0.624, 0.882, 0.796)
let tealStroke = color(0.059, 0.431, 0.337)
let tealText = color(0.016, 0.204, 0.173)
let tealSub = color(0.059, 0.431, 0.337)

func centered(
    _ text: String, x: CGFloat, y: CGFloat, w: CGFloat,
    font: NSFont, color: NSColor
) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: color
    ]
    let size = (text as NSString).size(withAttributes: attributes)
    (text as NSString).draw(
        at: NSPoint(x: x + (w - size.width) / 2, y: y),
        withAttributes: attributes
    )
}

func node(
    _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
    title: String, subtitle: String,
    fill: NSColor, stroke: NSColor,
    titleColor: NSColor, subtitleColor: NSColor,
    titleSize: CGFloat = 13
) {
    let rect = NSRect(x: x, y: y, width: w, height: h)
    let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
    fill.setFill()
    path.fill()
    stroke.setStroke()
    path.lineWidth = 0.5
    path.stroke()
    centered(
        title, x: x, y: y + 11, w: w,
        font: NSFont.systemFont(ofSize: titleSize, weight: .medium),
        color: titleColor
    )
    centered(
        subtitle, x: x, y: y + 32, w: w,
        font: NSFont.systemFont(ofSize: 11), color: subtitleColor
    )
}

func arrow(_ x1: CGFloat, _ y: CGFloat, _ x2: CGFloat, _ tint: NSColor) {
    let line = NSBezierPath()
    line.move(to: NSPoint(x: x1, y: y))
    line.line(to: NSPoint(x: x2 - 6, y: y))
    line.lineWidth = 1.5
    tint.setStroke()
    line.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: x2, y: y))
    head.line(to: NSPoint(x: x2 - 6, y: y - 3.5))
    head.line(to: NSPoint(x: x2 - 6, y: y + 3.5))
    head.close()
    tint.setFill()
    head.fill()
}

guard let context = CGContext(
    data: nil, width: Int(width), height: Int(height),
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("Failed to create bitmap context\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
defer { NSGraphicsContext.restoreGraphicsState() }

NSColor.white.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()

centered("修复前 · 每次按键", x: 40, y: 38, w: 200,
         font: NSFont.systemFont(ofSize: 12, weight: .medium), color: redText)

node(40, 60, 110, 56, title: "一次按键", subtitle: "query 改变",
     fill: redFill, stroke: redStroke, titleColor: redText, subtitleColor: redSub)
arrow(152, 88, 186, redStroke)
node(190, 60, 130, 56, title: "body 求值 ×6", subtitle: "计算属性被反复读",
     fill: redFill, stroke: redStroke, titleColor: redText, subtitleColor: redSub)
arrow(322, 88, 356, redStroke)
node(360, 60, 140, 56, title: "全量排序 ×18", subtitle: "335 万字符扫描",
     fill: redFill, stroke: redStroke, titleColor: redText, subtitleColor: redSub)
arrow(502, 88, 536, redStroke)
node(540, 60, 100, 56, title: "1784 ms", subtitle: "",
     fill: redFillStrong, stroke: redStroke, titleColor: redText,
     subtitleColor: redSub, titleSize: 15)

centered("修复后 · 每次按键", x: 40, y: 144, w: 200,
         font: NSFont.systemFont(ofSize: 12, weight: .medium), color: tealText)

node(40, 166, 110, 56, title: "一次按键", subtitle: "query 改变",
     fill: tealFill, stroke: tealStroke, titleColor: tealText, subtitleColor: tealSub)
arrow(152, 194, 186, tealStroke)
node(190, 166, 130, 56, title: "只读缓存", subtitle: "body 不再计算",
     fill: tealFill, stroke: tealStroke, titleColor: tealText, subtitleColor: tealSub)
arrow(322, 194, 356, tealStroke)
node(360, 166, 140, 56, title: "字节索引 ×1", subtitle: "Data.range(of:)",
     fill: tealFill, stroke: tealStroke, titleColor: tealText, subtitleColor: tealSub)
arrow(502, 194, 536, tealStroke)
node(540, 166, 100, 56, title: "3.9 ms", subtitle: "",
     fill: tealFillStrong, stroke: tealStroke, titleColor: tealText,
     subtitleColor: tealSub, titleSize: 15)

guard let small = context.makeImage() else { exit(1) }
// AppKit's flipped context writes into a bottom-left bitmap; flip once while
// scaling so the exported PNG is upright and Retina-independent.
let outWidth = Int(width * scale)
let outHeight = Int(height * scale)
guard let finalContext = CGContext(
    data: nil, width: outWidth, height: outHeight,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }
finalContext.translateBy(x: 0, y: CGFloat(outHeight))
finalContext.scaleBy(x: 1, y: -1)
finalContext.draw(
    small, in: CGRect(x: 0, y: 0, width: CGFloat(outWidth), height: CGFloat(outHeight))
)
guard let finalImage = finalContext.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: finalImage)
guard let png = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG\n", stderr)
    exit(1)
}
guard CommandLine.arguments.count > 1 else {
    fputs("Usage: make-perf-diagram <output.png>\n", stderr)
    exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    print("Wrote \(CommandLine.arguments[1]) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
} catch {
    fputs("Failed to write: \(error)\n", stderr)
    exit(1)
}
