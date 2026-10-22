import AppKit
let folder = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.scaleBy(x: CGFloat(pixels)/1024, y: CGFloat(pixels)/1024)
        NSColor(calibratedRed: 0.055, green: 0.09, blue: 0.16, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 64,y: 64,width: 896,height: 896), xRadius: 195,yRadius: 195).fill()
        NSColor.systemMint.setFill()
        for (x,y) in [(170,210),(390,340),(610,470)] {
            NSBezierPath(roundedRect: NSRect(x:x,y:y,width:245,height:48),xRadius:12,yRadius:12).fill()
        }
        NSColor(calibratedRed: 1,green: 0.78,blue: 0.23,alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x:235,y:495,width:230,height:230)).fill()
        NSColor(calibratedRed: 0.6,green: 0.34,blue: 0.05,alpha: 1).setStroke()
        let coin = NSBezierPath(ovalIn: NSRect(x:270,y:530,width:160,height:160)); coin.lineWidth=15;coin.stroke()
        NSColor.white.setStroke()
        let arrow=NSBezierPath();arrow.move(to:NSPoint(x:550,y:650));arrow.line(to:NSPoint(x:770,y:800));arrow.move(to:NSPoint(x:650,y:800));arrow.line(to:NSPoint(x:770,y:800));arrow.line(to:NSPoint(x:770,y:680));arrow.lineWidth=42;arrow.lineCapStyle = .round;arrow.lineJoinStyle = .round;arrow.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: folder+"/icon_\(size)x\(size)\(suffix).png"))
    }
}
