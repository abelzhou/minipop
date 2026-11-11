import Cocoa

let iconset = "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

func makeIcon(size: Int, scale: Int) {
    let px = size * scale
    let img = NSImage(size: NSSize(width: px, height: px))
    img.lockFocus()

    let inset = CGFloat(px) * 0.08
    let rect = NSRect(x: inset, y: inset, width: CGFloat(px) - inset * 2, height: CGFloat(px) - inset * 2)
    let radius = rect.width * 0.225
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // Pure white background with subtle light border
    NSColor.white.setFill()
    path.fill()
    NSColor(calibratedWhite: 0.88, alpha: 1.0).setStroke()
    path.lineWidth = max(1, CGFloat(px) * 0.015)
    path.stroke()

    let str = "✨" as NSString
    let font = NSFont.systemFont(ofSize: CGFloat(px) * 0.54)
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    let sSize = str.size(withAttributes: attrs)
    let sRect = NSRect(
        x: (CGFloat(px) - sSize.width) / 2,
        y: (CGFloat(px) - sSize.height) / 2,
        width: sSize.width,
        height: sSize.height
    )
    str.draw(in: sRect, withAttributes: attrs)

    img.unlockFocus()
    if let tiff = img.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        try? png.write(to: URL(fileURLWithPath: "\(iconset)/\(name)"))
    }
}

for s in [16, 32, 128, 256, 512] {
    makeIcon(size: s, scale: 1)
    makeIcon(size: s, scale: 2)
}
