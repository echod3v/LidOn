// 앱 아이콘 생성: swift scripts/make-icon.swift  →  Resources/AppIcon.icns, Resources/AppIcon.png
// 디자인: 앱 안의 "빛나는 구슬 + 노트북" 모티프와 같은 모양
import AppKit

let size: CGFloat = 1024
let mint = NSColor(calibratedRed: 0.36, green: 0.93, blue: 0.78, alpha: 1)
let teal = NSColor(calibratedRed: 0.08, green: 0.62, blue: 0.70, alpha: 1)
let indigo = NSColor(calibratedRed: 0.40, green: 0.42, blue: 0.98, alpha: 1)

let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    let ctx = NSGraphicsContext.current!.cgContext
    // macOS 아이콘 그리드: 824pt 둥근 사각형
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set()
    NSGradient(colors: [NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.16, alpha: 1),
                        NSColor(calibratedRed: 0.06, green: 0.20, blue: 0.27, alpha: 1)])!.draw(in: squircle, angle: 90)
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGraphicsContext.current?.saveGraphicsState()
    squircle.addClip()
    let center = NSPoint(x: 512, y: 540)

    // 번지는 빛
    NSGradient(colors: [mint.withAlphaComponent(0.45), teal.withAlphaComponent(0.12), .clear])!
        .draw(fromCenter: center, radius: 0, toCenter: center, radius: 470, options: [])

    // 물결 고리
    for (i, r) in [400.0, 330.0].enumerated() {
        let ring = NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        ring.lineWidth = 10
        mint.withAlphaComponent(i == 0 ? 0.16 : 0.28).setStroke()
        ring.stroke()
    }
    // 회전 테두리 빛 (각진 그라데이션 대신 두 색 원호)
    let rr: CGFloat = 262
    ctx.saveGState()
    let arc = CGMutablePath()
    arc.addEllipse(in: CGRect(x: center.x - rr, y: center.y - rr, width: rr * 2, height: rr * 2))
    ctx.addPath(arc)
    ctx.setLineWidth(26)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let colors = [mint.cgColor, teal.cgColor, indigo.cgColor, mint.cgColor] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.35, 0.7, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: center.x - rr, y: center.y + rr), end: CGPoint(x: center.x + rr, y: center.y - rr), options: [])
    ctx.restoreGState()

    // 코어
    let core: CGFloat = 225
    NSGradient(colors: [mint.withAlphaComponent(0.95), teal])!
        .draw(in: NSBezierPath(ovalIn: NSRect(x: center.x - core, y: center.y - core, width: core * 2, height: core * 2)),
              relativeCenterPosition: NSPoint(x: -0.4, y: 0.4))

    // 노트북: 화면
    let screen = NSRect(x: center.x - 160, y: center.y - 40, width: 320, height: 205)
    let screenPath = NSBezierPath(roundedRect: screen, xRadius: 20, yRadius: 20)
    NSGradient(colors: [NSColor(white: 0.16, alpha: 1), NSColor(white: 0.06, alpha: 1)])!.draw(in: screenPath, angle: -90)
    screenPath.lineWidth = 10
    NSColor.white.withAlphaComponent(0.9).setStroke()
    screenPath.stroke()
    // 화면 속 "켜짐" 빛
    NSGraphicsContext.current?.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = mint
    glow.shadowBlurRadius = 28
    glow.set()
    mint.setFill()
    NSBezierPath(roundedRect: NSRect(x: center.x - 50, y: screen.midY - 8, width: 100, height: 16), xRadius: 8, yRadius: 8).fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    // 노트북: 본체
    let base = NSRect(x: center.x - 205, y: center.y - 68, width: 410, height: 26)
    NSGradient(colors: [NSColor.white, NSColor(white: 0.78, alpha: 1)])!
        .draw(in: NSBezierPath(roundedRect: base, xRadius: 13, yRadius: 13), angle: -90)
    NSColor.black.withAlphaComponent(0.25).setFill()
    NSBezierPath(roundedRect: NSRect(x: center.x - 36, y: base.maxY - 9, width: 72, height: 7), xRadius: 3.5, yRadius: 3.5).fill()

    NSGraphicsContext.current?.restoreGraphicsState()
    return true
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
func png(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
for (px, name) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"),
                   (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")] {
    try! png(px).write(to: iconset.appendingPathComponent("icon_\(name).png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! p.run()
p.waitUntilExit()
try! png(512).write(to: URL(fileURLWithPath: "Resources/AppIcon.png"))
print("Resources/AppIcon.icns, Resources/AppIcon.png")
