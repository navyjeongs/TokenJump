import AppKit

// Build-time renderer for the deliberately small SVG vocabulary used by our sprites.
// SVGs remain the source of truth; the game loads cached PNG textures, never a web view.
final class SVG: NSObject, XMLParserDelegate {
    var width = 0.0, height = 0.0
    var shapes: [(String, [String: String])] = []
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        if name == "svg" { width = Double(a["width"] ?? "0") ?? 0; height = Double(a["height"] ?? "0") ?? 0 }
        else if ["rect", "circle", "polygon", "line"].contains(name) { shapes.append((name, a)) }
        else { fatalError("Unsupported SVG element: \(name)") }
    }
    func color(_ hex: String) -> NSColor {
        let value = UInt32(hex.replacingOccurrences(of: "#", with: ""), radix: 16)!
        return NSColor(calibratedRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
    func png() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * 3), pixelsHigh: Int(height * 3), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: 3, y: 3); context.cgContext.translateBy(x: 0, y: height); context.cgContext.scaleBy(x: 1, y: -1)
        for (name, a) in shapes {
            func n(_ key: String) -> CGFloat { CGFloat(Double(a[key] ?? "0") ?? 0) }
            let path: NSBezierPath
            switch name {
            case "rect": path = NSBezierPath(roundedRect: NSRect(x: n("x"), y: n("y"), width: n("width"), height: n("height")), xRadius: n("rx"), yRadius: n("rx"))
            case "circle": path = NSBezierPath(ovalIn: NSRect(x: n("cx") - n("r"), y: n("cy") - n("r"), width: n("r") * 2, height: n("r") * 2))
            case "line": path = NSBezierPath(); path.move(to: NSPoint(x: n("x1"), y: n("y1"))); path.line(to: NSPoint(x: n("x2"), y: n("y2")))
            default:
                path = NSBezierPath()
                let points = (a["points"] ?? "").split { $0 == "," || $0.isWhitespace }.map { CGFloat(Double($0)!) }
                for i in stride(from: 0, to: points.count, by: 2) { let p = NSPoint(x: points[i], y: points[i + 1]); if i == 0 { path.move(to: p) } else { path.line(to: p) } }
                path.close()
            }
            if name != "line", let fill = a["fill"], fill != "none" { color(fill).setFill(); path.fill() }
            if let stroke = a["stroke"], stroke != "none" { color(stroke).setStroke(); path.lineWidth = CGFloat(Double(a["stroke-width"] ?? "1")!); path.lineJoinStyle = .round; path.lineCapStyle = .round; path.stroke() }
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }
}
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let target = URL(fileURLWithPath: CommandLine.arguments[2])
try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
for file in try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "svg" }) {
    let drawing = SVG(); let parser = XMLParser(data: try Data(contentsOf: file)); parser.delegate = drawing
    guard parser.parse(), drawing.width > 0, drawing.height > 0 else { fatalError("Invalid SVG: \(file.lastPathComponent)") }
    try drawing.png().write(to: target.appendingPathComponent(file.deletingPathExtension().lastPathComponent + ".png"))
}

// A documentation preview, rendered offscreen from the same generated textures.
if CommandLine.arguments.count > 3 {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1280, pixelsHigh: 440, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context; context.cgContext.scaleBy(x: 2, y: 2)
    NSColor(calibratedRed: 0.06, green: 0.075, blue: 0.10, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 640, height: 220).fill()
    let items: [(String, String, NSRect)] = [
        ("platform", "일반 발판", NSRect(x: 18, y: 160, width: 124, height: 31)),
        ("platform-rail", "레일 발판", NSRect(x: 178, y: 160, width: 124, height: 31)),
        ("platform-ice", "얼음 발판", NSRect(x: 338, y: 160, width: 124, height: 31)),
        ("platform-goal", "목표 발판", NSRect(x: 498, y: 160, width: 124, height: 31)),
        ("cannon", "대포", NSRect(x: 44, y: 43, width: 72, height: 60)),
        ("cannonball", "포탄", NSRect(x: 222, y: 55, width: 36, height: 36)),
        ("spikes", "가시", NSRect(x: 376, y: 55, width: 48, height: 36)),
        ("goal-flag", "깃발", NSRect(x: 542, y: 43, width: 36, height: 52))
    ]
    let style = NSMutableParagraphStyle(); style.alignment = .center
    for (index, item) in items.enumerated() {
        NSImage(contentsOf: target.appendingPathComponent(item.0 + ".png"))!.draw(in: item.2)
        (item.1 as NSString).draw(in: NSRect(x: (index % 4) * 160, y: index < 4 ? 131 : 18, width: 160, height: 18), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.lightGray, .paragraphStyle: style])
    }
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
}
